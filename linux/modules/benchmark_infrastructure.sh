# Linux Benchmark Infrastructure
# Bash equivalents of BenchmarkInfrastructure.psm1

LAST_PREWARM_RESULT=""

build_mock_server() {
    local bench_dir="$1"
    local bin_dir="$bench_dir/bin/linux"
    local output="$bin_dir/mock-server"
    local src_dir="$bench_dir/mock-server"

    mkdir -p "$bin_dir"

    if [ -f "$output" ]; then
        newer=$(find "$src_dir" -name "*.go" -newer "$output" 2>/dev/null | head -1)
        [ -z "$newer" ] && echo "$output" && return 0
        echo "Mock server source changed, rebuilding..." >&2
    fi

    echo "Building mock server..." >&2
    (cd "$src_dir" && GOOS=linux GOARCH=amd64 go build -o "$output" ./main.go) || return 1
    echo "Mock server built: $output" >&2
    echo "$output"
}

start_mock_server_process() {
    local exe_path="$1"
    local port="${2:-9099}"
    local models="${3:-}"

    export MOCK_PORT="$port"
    export MOCKER_PORT="$port"
    [ -n "$models" ] && export MOCK_MODELS="$models"

    "$exe_path" > /dev/null 2>&1 &
    echo $!
}

invoke_benchmark() {
    local name="$1"
    local port="$2"
    local output_path="$3"
    local rate="$4"
    local duration="$5"
    local concurrency="${6:-256}"
    local model="${7:-openai/gpt-4o-mini}"
    local path="${8:-v1/chat/completions}"
    local auth="${9:-sk-bench-test-key}"
    local warmup="${10:-25}"
    local cli_path="${11}"
    local mock_url="${12:-}"
    local phase="${13:-Benchmark}"
    local extra_headers="${14-}"

    [ ! -f "$cli_path" ] && echo "ERROR: Benchmark CLI not found at $cli_path" && return 1

    echo "  [$phase] ${rate}req/s x ${duration}s @ ${concurrency} workers"

    local header_args=()
    [ -n "$extra_headers" ] && while IFS='|' read -ra hdrs; do
        for h in "${hdrs[@]}"; do
            [ -n "$h" ] && header_args+=(-header "$h")
        done
    done <<< "$extra_headers"

    "$cli_path" \
        -port "$port" \
        -rate "$rate" \
        -duration "$duration" \
        -concurrency "$concurrency" \
        -model "$model" \
        -path "$path" \
        -auth "$auth" \
        -warmup "$warmup" \
        -output "$output_path" \
        -quiet \
        "${header_args[@]}" 2>&1

    local exit_code=$?
    [ $exit_code -ne 0 ] && echo "ERROR: Benchmark CLI for $name failed with exit code $exit_code" && return 1

    local result
    result=$(jq '.' "$output_path" 2>/dev/null) || return 0

    local total_requests success_rate rps p50 p90 p95 p99 p999 max mean
    local status_200 status_4xx status_5xx allocs bytes err_count

    total_requests=$(echo "$result" | jq -r '.requests // 0')
    success_rate=$(echo "$result" | jq -r '.success_rate // 0')
    rps=$(echo "$result" | jq -r '.throughput_rps // 0')
    p50=$(echo "$result" | jq -r '.p50_latency_ms // 0')
    p90=$(echo "$result" | jq -r '.p90_latency_ms // 0')
    p95=$(echo "$result" | jq -r '.p95_latency_ms // 0')
    p99=$(echo "$result" | jq -r '.p99_latency_ms // 0')
    p999=$(echo "$result" | jq -r '.p999_latency_ms // 0')
    max=$(echo "$result" | jq -r '.max_latency_ms // 0')
    mean=$(echo "$result" | jq -r '.mean_latency_ms // 0')
    status_200=$(echo "$result" | jq -r '.status_200 // 0')
    status_4xx=$(echo "$result" | jq -r '.status_4xx // 0')
    status_5xx=$(echo "$result" | jq -r '.status_5xx // 0')
    allocs=$(echo "$result" | jq -r '.allocs_per_op // 0')
    bytes=$(echo "$result" | jq -r '.bytes_per_op // 0')
    err_count=$(echo "$result" | jq -r '[.error_breakdown[]?.count] | add // 0')

    if [ "$phase" = "Prewarm" ]; then
        printf "  OK  %5d req  %6.2f%%%% | RPS %6.1f/%-4d | P50=%6.2f P90=%6.2f P95=%6.2f P99=%6.2f mean=%6.2f | Status %d/%d/%d/%d\n" \
            "$total_requests" "$success_rate" \
            "$rps" "$rate" \
            "$p50" "$p90" "$p95" "$p99" "$mean" \
            "$status_200" "$status_4xx" "$status_5xx" "$err_count"

        LAST_PREWARM_RESULT=$(cat <<PRERESULT
{"requests":$total_requests,"success_rate":$success_rate,"throughput_rps":$rps,"p50_latency_ms":$p50,"p90_latency_ms":$p90,"p95_latency_ms":$p95,"p99_latency_ms":$p99,"p999_latency_ms":$p999,"max_latency_ms":$max,"mean_latency_ms":$mean,"allocs_per_op":$allocs,"bytes_per_op":$bytes,"status_200":$status_200,"status_4xx":$status_4xx,"status_5xx":$status_5xx}
PRERESULT
)
    else
        local pre_rps="" pre_success="" pre_mean="" pre_p50="" pre_p90="" pre_p95="" pre_p99="" pre_p999="" pre_max="" pre_allocs="" pre_bytes="" pre_requests="" pre_s200="" pre_s4xx="" pre_s5xx=""
        if [ -n "$LAST_PREWARM_RESULT" ]; then
            pre_rps=$(echo "$LAST_PREWARM_RESULT" | jq -r '.throughput_rps // empty')
            pre_success=$(echo "$LAST_PREWARM_RESULT" | jq -r '.success_rate // empty')
            pre_mean=$(echo "$LAST_PREWARM_RESULT" | jq -r '.mean_latency_ms // empty')
            pre_p50=$(echo "$LAST_PREWARM_RESULT" | jq -r '.p50_latency_ms // empty')
            pre_p90=$(echo "$LAST_PREWARM_RESULT" | jq -r '.p90_latency_ms // empty')
            pre_p95=$(echo "$LAST_PREWARM_RESULT" | jq -r '.p95_latency_ms // empty')
            pre_p99=$(echo "$LAST_PREWARM_RESULT" | jq -r '.p99_latency_ms // empty')
            pre_p999=$(echo "$LAST_PREWARM_RESULT" | jq -r '.p999_latency_ms // empty')
            pre_max=$(echo "$LAST_PREWARM_RESULT" | jq -r '.max_latency_ms // empty')
            pre_allocs=$(echo "$LAST_PREWARM_RESULT" | jq -r '.allocs_per_op // empty')
            pre_bytes=$(echo "$LAST_PREWARM_RESULT" | jq -r '.bytes_per_op // empty')
            pre_requests=$(echo "$LAST_PREWARM_RESULT" | jq -r '.requests // empty')
            pre_s200=$(echo "$LAST_PREWARM_RESULT" | jq -r '.status_200 // 0')
            pre_s4xx=$(echo "$LAST_PREWARM_RESULT" | jq -r '.status_4xx // 0')
            pre_s5xx=$(echo "$LAST_PREWARM_RESULT" | jq -r '.status_5xx // 0')
        fi

        printf "  %s\n" "------------------------------------------------------"
        printf "  %-28s  %12s  %12s\n" "Metric" "Benchmark" "Prewarm"
        printf "  %s\n" "------------------------------------------------------"

        _print_bench_row "Throughput (req/s)" "$rps" "$pre_rps" "%.2f"
        _print_bench_row "Success rate (%)" "$success_rate" "$pre_success" "%.2f"
        _print_bench_row "Mean latency (ms)" "$mean" "$pre_mean" "%.3f"
        _print_bench_row "P50 latency (ms)" "$p50" "$pre_p50" "%.3f"
        _print_bench_row "P90 latency (ms)" "$p90" "$pre_p90" "%.3f"
        _print_bench_row "P95 latency (ms)" "$p95" "$pre_p95" "%.3f"
        _print_bench_row "P99 latency (ms)" "$p99" "$pre_p99" "%.3f"
        _print_bench_row "P999 latency (ms)" "$p999" "$pre_p999" "%.3f"
        _print_bench_row "Max latency (ms)" "$max" "$pre_max" "%.3f"
        _print_bench_row "Allocs/op" "$allocs" "$pre_allocs" "%.1f"
        _print_bench_row "Bytes/op" "$bytes" "$pre_bytes" "%.0f"
        _print_bench_row "Requests" "$total_requests" "$pre_requests" "%.0f"

        printf "  %s\n" "------------------------------------------------------"
        printf "  %-28s  %12s  %12s\n" "Status codes" "$status_200/$status_4xx/$status_5xx/$err_count" "$pre_s200/$pre_s4xx/$pre_s5xx/0"

        echo "$result" | jq -r '.error_breakdown[]? | select(.count > 0) | "  [" + (.count|tostring) + "x] " + .message' 2>/dev/null | while read -r line; do
            printf "  %-28s     %s\n" "" "$line"
        done
    fi

    return 0
}

_print_bench_row() {
    local label="$1" val="$2" prev="$3" fmt="$4"
    local v p
    if [ -n "$val" ] && [ "$val" != "0" ] 2>/dev/null; then
        v=$(printf "$fmt" "$val" 2>/dev/null)
    else
        v=""
    fi
    if [ -n "$prev" ] && [ "$prev" != "0" ] 2>/dev/null; then
        p=$(printf "$fmt" "$prev" 2>/dev/null)
    else
        p=""
    fi
    printf "  %-28s  %12s  %12s\n" "$label" "${v:-N/A}" "${p:-N/A}"
}

clear_bench_binaries() {
    local bench_dir="$1"
    local bin_dir="$bench_dir/bin/linux"
    if [ -d "$bin_dir" ]; then
        rm -f "$bin_dir"/*
        echo "  Cleaned binaries in $bin_dir"
    fi
}

build_all_binaries() {
    local bench_dir="$1"
    local bin_dir="$bench_dir/bin/linux"
    mkdir -p "$bin_dir"

    local mock_out="$bin_dir/mock-server"
    echo "  Building mock server..."
    (cd "$bench_dir/mock-server" && GOOS=linux GOARCH=amd64 go build -o "$mock_out" ./main.go) || return 1

    local cli_out="$bin_dir/aurora-bench-cli"
    echo "  Building benchmark CLI..."
    (cd "$bench_dir" && GOOS=linux GOARCH=amd64 go build -o "$cli_out" "$bench_dir/tools/benchmark-cli") || return 1

    local aurora_out="$bin_dir/aurora-bench"
    if [ -f "$aurora_out" ]; then
        echo "  Using pre-built Aurora: $aurora_out"
    else
        echo "  WARNING: No pre-built Aurora binary found. Place one at $aurora_out"
    fi

    echo "  All binaries built fresh."
    echo "mock_server=$mock_out"
    echo "bench_cli=$cli_out"
    [ -f "$aurora_out" ] && echo "aurora=$aurora_out"
}

verify_mock_server_model() {
    local port="${1:-9099}"
    local expected_model="${2:-gpt-4o-mini}"
    local endpoint_path="${3:-v1/chat/completions}"

    local url="http://127.0.0.1:$port/$endpoint_path"
    local body
    body=$(printf '{"model":"%s","messages":[{"role":"user","content":"verify model"}],"stream":false}' "$expected_model")

    echo "  Verifying mock server model at $url..."

    local response
    response=$(curl -sf -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null) || {
        echo "  Mock server verification FAILED: curl error"
        return 1
    }

    local response_model
    response_model=$(echo "$response" | jq -r '.model // empty' 2>/dev/null)

    if [ "$response_model" != "$expected_model" ]; then
        echo "  Model MISMATCH: sent '$expected_model', got '$response_model'"
        return 1
    fi

    echo "  Mock server model OK: '$response_model'"
    return 0
}
