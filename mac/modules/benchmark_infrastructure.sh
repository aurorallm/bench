#!/usr/bin/env bash
# macOS Benchmark Infrastructure

build_mock_server() {
    local bench_dir="$1"
    local mock_out="$bench_dir/bin/darwin/mock-server"
    if [ -f "$mock_out" ]; then
        echo "$mock_out"
        return 0
    fi
    echo "  Building mock server..." >&2
    mkdir -p "$bench_dir/bin/darwin"
    (cd "$bench_dir/mock-server" && go build -o "$mock_out" ./main.go) >/dev/null 2>&1
    echo "$mock_out"
}

start_mock_server_process() {
    local exe_path="$1" port="$2" models="$3"
    "$exe_path" -port "$port" -models "$models" > /dev/null 2>&1 &
    echo $!
}

invoke_benchmark() {
    local name="$1" port="$2" output="$3" rate="$4" duration="$5" concurrency="$6"
    local model="$7" bench_path="$8" auth="$9" warmup="${10}" cli="${11}" mock_url="${12}" phase="${13:-Benchmark}"

    echo "  [$phase] $name: $rate req/s x ${duration}s..."

    "$cli" \
        -target "http://127.0.0.1:$port/$bench_path" \
        -rate "$rate" \
        -duration "$duration" \
        -concurrency "$concurrency" \
        -model "$model" \
        -auth "$auth" \
        -warmup "$warmup" \
        -output "$output" 2>&1 | tail -5

    if [ -f "$output" ]; then
        local total
        total=$(jq -r '.total_requests // .requests_total // "N/A"' "$output" 2>/dev/null)
        echo "  [$phase] $name complete: $total requests -> $output"
    else
        echo "  [$phase] WARNING: $name produced no output file"
    fi
}

clear_bench_binaries() {
    local bench_dir="$1"
    local bin_dir="$bench_dir/bin/darwin"
    echo "  Clearing $bin_dir..."
    rm -f "$bin_dir"/* 2>/dev/null || true
    echo "  Cleared."
}

build_all_binaries() {
    local bench_dir="$1"
    build_mock_server "$bench_dir" > /dev/null
    build_bench_cli "$bench_dir" > /dev/null
    echo "  All binaries built for darwin."
}

verify_mock_server_model() {
    local port="$1" expected="$2"
    local url="http://127.0.0.1:$port/v1/chat/completions"
    body=$(new_chat_body "$expected" "verify-model")
    local response
    response=$(curl -sf -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer sk-bench-test-key" \
        -d "$body" 2>/dev/null || echo "")
    local actual
    actual=$(echo "$response" | jq -r '.model // .error // "unknown"' 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "  Model verified: $expected"
        return 0
    elif echo "$actual" | grep -qi "$expected"; then
        echo "  Model verified (fuzzy): $actual"
        return 0
    else
        echo "  Model mismatch: expected '$expected', got '$actual'"
        return 1
    fi
}
