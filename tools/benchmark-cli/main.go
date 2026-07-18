// bench-cli is a standalone HTTP benchmark tool using Aurora's internal
// high-precision timer (QueryPerformanceCounter on Windows) for nanosecond
// latency measurement. Replaces external bifrost-benchmarking/benchmark.exe
// which uses time.Now() (~15ms tick on Windows).
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"

	"aurora-bench/internal/benchmark"
)

type jsonResult struct {
	Requests       uint64             `json:"requests"`
	Rate           float64            `json:"rate"`
	SuccessRate    float64            `json:"success_rate"`
	MeanLatencyMs  float64            `json:"mean_latency_ms"`
	P50LatencyMs   float64            `json:"p50_latency_ms"`
	P90LatencyMs   float64            `json:"p90_latency_ms"`
	P95LatencyMs   float64            `json:"p95_latency_ms"`
	P99LatencyMs   float64            `json:"p99_latency_ms"`
	P999LatencyMs  float64            `json:"p999_latency_ms"`
	MaxLatencyMs   float64            `json:"max_latency_ms"`
	ThroughputRPS  float64            `json:"throughput_rps"`
	Timestamp      string             `json:"timestamp"`
	Status200      uint64             `json:"status_200"`
	Status4xx      uint64             `json:"status_4xx"`
	Status5xx      uint64             `json:"status_5xx"`
	StatusOther    uint64             `json:"status_other"`
	AllocsPerOp    float64            `json:"allocs_per_op"`
	BytesPerOp     float64            `json:"bytes_per_op"`
	ErrorBreakdown []errorBreakdownEntry `json:"error_breakdown,omitempty"`
}

type errorBreakdownEntry struct {
	Message string `json:"message"`
	Count   int    `json:"count"`
}

var headers headerFlag

func init() {
	flag.Var(&headers, "header", "Extra header in key=value format (can be repeated)")
}

type headerFlag []string

func (h *headerFlag) String() string {
	return fmt.Sprintf("%v", *h)
}

func (h *headerFlag) Set(value string) error {
	*h = append(*h, value)
	return nil
}

func main() {
	host := flag.String("host", "127.0.0.1", "Host to benchmark")
	port := flag.Int("port", 8080, "Port to benchmark")
	rate := flag.Int("rate", 1000, "Target request rate (req/s)")
	duration := flag.Int("duration", 10, "Duration in seconds")
	concurrency := flag.Int("concurrency", 64, "Number of concurrent workers")
	model := flag.String("model", "gpt-4o-mini", "Model name in payload")
	path := flag.String("path", "v1/chat/completions", "API path (no leading /)")
	auth := flag.String("auth", "", "Bearer token for Authorization header")
	output := flag.String("output", "", "Output JSON file path (default: stdout)")
	warmup := flag.Int("warmup", 5, "Warmup requests (count)")
	deployment := flag.String("deployment", "", "Deployment name (for Azure OpenAI)")
	quiet := flag.Bool("quiet", false, "Suppress all terminal output (only write JSON to file)")
	flag.Parse()

	if flag.NArg() > 0 || *host == "" || *port == 0 {
		flag.Usage()
		os.Exit(1)
	}

	body := buildRequestBody(*model, *deployment)

	// Parse extra headers from -header flags
	parsedHeaders := make(map[string]string)
	for _, h := range headers {
		parts := strings.SplitN(h, ":", 2)
		if len(parts) == 2 {
			parsedHeaders[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}

	// Warmup (serial requests)
	if *warmup > 0 {
		warmupURL := fmt.Sprintf("http://%s:%d/%s", *host, *port, *path)
		for i := 0; i < *warmup; i++ {
			req, _ := http.NewRequest("POST", warmupURL, strings.NewReader(string(body)))
			req.Header.Set("Content-Type", "application/json")
			if *auth != "" {
				req.Header.Set("Authorization", "Bearer "+*auth)
			}
			for k, v := range parsedHeaders {
				req.Header.Set(k, v)
			}
			resp, err := http.DefaultClient.Do(req)
			if err == nil {
				_, _ = io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
			}
		}
	}

	targetRPS := float64(*rate)

	cfg := benchmark.LoadTestConfig{
		Concurrency: *concurrency,
		Duration:    time.Duration(*duration) * time.Second,
		Endpoint:    "/" + *path,
		Method:      "POST",
		RequestBody: body,
		AuthHeader:  authHeader(*auth),
		Headers:     parsedHeaders,
		Mode:        benchmark.ModeHTTP,
		TargetURL:   fmt.Sprintf("http://%s:%d", *host, *port),
		TargetRPS:   targetRPS,
	}

	ctx := context.Background()
	if !*quiet {
		fmt.Fprintf(os.Stderr, "Benchmark: %d req/s × %ds @ %s:%d/%s\n", *rate, *duration, *host, *port, *path)
	}
	result, err := benchmark.RunLoadTest(ctx, cfg)
	if err != nil {
		log.Fatalf("benchmark failed: %v", err)
	}

	// Build JSON output
	jr := jsonResult{
		Requests:      result.TotalRequests,
		Rate:          float64(*rate),
		SuccessRate:   safePct(result.SuccessCount, result.TotalRequests),
		MeanLatencyMs: result.Avg.Seconds() * 1000,
		P50LatencyMs:  result.P50.Seconds() * 1000,
		P90LatencyMs:  result.P90.Seconds() * 1000,
		P95LatencyMs:  result.P95.Seconds() * 1000,
		P99LatencyMs:  result.P99.Seconds() * 1000,
		P999LatencyMs: result.P999.Seconds() * 1000,
		MaxLatencyMs:  result.Max.Seconds() * 1000,
		ThroughputRPS: result.Throughput,
		Timestamp:     time.Now().Format(time.RFC3339),
		Status200:     result.Status200,
		Status4xx:     result.Status4xx,
		Status5xx:     result.Status5xx,
		StatusOther:   result.StatusOther,
		AllocsPerOp:   result.AllocsPerOp,
		BytesPerOp:    result.BytesPerOp,
	}

	// Sort and limit error breakdown to top entries
	if len(result.ErrorBreakdown) > 0 {
		sort.Slice(result.ErrorBreakdown, func(i, j int) bool {
			return result.ErrorBreakdown[i].Count > result.ErrorBreakdown[j].Count
		})
		for _, e := range result.ErrorBreakdown {
			jr.ErrorBreakdown = append(jr.ErrorBreakdown, errorBreakdownEntry{
				Message: truncate(e.Message, 120),
				Count:   e.Count,
			})
		}
	}

	// Print terminal summary (always to stderr so it doesn't pollute JSON on stdout)
	if !*quiet {
		fmt.Fprintf(os.Stderr, "\n")
		fmt.Fprintf(os.Stderr, "  Requests:      %d\n", jr.Requests)
		fmt.Fprintf(os.Stderr, "  Target rate:   %d/s\n", *rate)
		fmt.Fprintf(os.Stderr, "  Actual RPS:    %.2f/s\n", jr.ThroughputRPS)
		fmt.Fprintf(os.Stderr, "  Success:       2xx=%d  4xx=%d  5xx=%d  other=%d\n", jr.Status200, jr.Status4xx, jr.Status5xx, jr.StatusOther)
		fmt.Fprintf(os.Stderr, "  Success rate:  %.2f%%\n", jr.SuccessRate)
		fmt.Fprintf(os.Stderr, "  Latency (ms):  P50=%.3f  P90=%.3f  P95=%.3f  P99=%.3f  P999=%.3f  max=%.3f\n",
			jr.P50LatencyMs, jr.P90LatencyMs, jr.P95LatencyMs, jr.P99LatencyMs, jr.P999LatencyMs, jr.MaxLatencyMs)
		fmt.Fprintf(os.Stderr, "  Allocs/op:     %.0f\n", jr.AllocsPerOp)
		fmt.Fprintf(os.Stderr, "  Bytes/op:      %.0f\n", jr.BytesPerOp)
		if len(jr.ErrorBreakdown) > 0 {
			fmt.Fprintf(os.Stderr, "  Errors:\n")
			for _, e := range jr.ErrorBreakdown {
				fmt.Fprintf(os.Stderr, "    %d×  %s\n", e.Count, e.Message)
			}
		}
		fmt.Fprintf(os.Stderr, "\n")
	}

	// Write JSON output
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")

	if *output != "" {
		f, err := os.Create(*output)
		if err != nil {
			log.Fatalf("cannot create output file: %v", err)
		}
		defer f.Close()
		enc = json.NewEncoder(f)
		enc.SetIndent("", "  ")
		if err := enc.Encode(jr); err != nil {
			log.Fatalf("cannot encode output: %v", err)
		}
		if !*quiet {
			fmt.Fprintf(os.Stderr, "Results saved to: %s\n", *output)
		}
	} else {
		if err := enc.Encode(jr); err != nil {
			log.Fatalf("cannot encode output: %v", err)
		}
	}
}

func buildRequestBody(model, deployment string) []byte {
	m := model
	if deployment != "" {
		m = deployment
	}
	body, _ := json.Marshal(map[string]interface{}{
		"model": m,
		"messages": []map[string]string{
			{"role": "user", "content": "benchmark request"},
		},
	})
	return body
}

func authHeader(token string) string {
	if token == "" {
		return ""
	}
	return "Bearer " + token
}

func safePct(num, denom uint64) float64 {
	if denom == 0 {
		return 0
	}
	return float64(num) / float64(denom) * 100
}

func truncate(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) <= maxLen {
		return s
	}
	return string(runes[:maxLen]) + "..."
}
