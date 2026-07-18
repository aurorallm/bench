#!/usr/bin/env bash
# macOS Benchmark Comparison - requires jq

read_benchmark_result() {
    local path="$1"
    jq '.' "$path" 2>/dev/null
}

write_generic_comparison() {
    local results_json="$1"
    local output_path="$2"
    local rate="$3"
    local duration="$4"
    local model="$5"
    local endpoint="$6"

    local names
    names=$(echo "$results_json" | jq -r 'keys | join(" ")')
    local base_name
    base_name=$(echo "$names" | awk '{print $1}')

    local machine_info
    machine_info=$(cat <<JSON
{
  "hostname": "$(hostname)",
  "os": "$(uname -a)",
  "arch": "$(uname -m)",
  "logical_processors": $(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1)
}
JSON
)

    local comparison
    comparison=$(cat <<COMPJSON
{
  "metadata": {
    "generated_at": "$(date -Iseconds)",
    "gateways": $(echo "$names" | jq -R 'split(" ")'),
    "baseline": "$base_name",
    "tool": "aurora-bench-cli (POSIX-timed)",
    "machine": $machine_info,
    "config": {
      "rate": $rate,
      "duration_seconds": $duration,
      "model": "$model",
      "endpoint": "$endpoint"
    }
  },
  "results": $results_json,
  "deltas": {}
}
COMPJSON
)

    echo "$comparison" | jq '.' > "$output_path"
    echo "Comparison written to: $output_path"
}

write_comparison_summary() {
    local path="$1"
    if [ -f "$path" ]; then
        echo ""
        echo "  Comparison summary: $path"
        jq -r '
          "  Config: \(.metadata.config.rate) req/s x \(.metadata.config.duration_seconds)s",
          "  Model: \(.metadata.config.model)",
          "  Host: \(.metadata.machine.hostname) (\(.metadata.machine.logical_processors) CPUs)",
          "",
          (.results | to_entries[] | "  \(.key): \(.value.throughput_rps) req/s, p50=\(.value.p50_latency_ms)ms, p99=\(.value.p99_latency_ms)ms")
        ' "$path"
        echo ""
    fi
}
