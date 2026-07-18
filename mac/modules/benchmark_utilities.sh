#!/usr/bin/env bash
# macOS Benchmark Utilities

wait_for_health() {
    local name="$1" port="$2" timeout="${3:-30}" health_path="${4:-health}" check_type="${5:-http}"
    local elapsed=0
    local health_url="http://127.0.0.1:$port/$health_path"
    echo -n "  Waiting for $name... "
    while [ $elapsed -lt "$timeout" ]; do
        if [ "$check_type" = "tcp" ]; then
            timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null && { echo "OK (${elapsed}s)"; return 0; }
        else
            local code
            code=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 1 "$health_url" 2>/dev/null || echo "000")
            if [ "$code" != "000" ]; then
                echo "OK (${elapsed}s, HTTP $code)"
                return 0
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "TIMEOUT (${timeout}s)"
    return 1
}

new_chat_body() {
    local model="$1" msg="${2:-Hello}"
    jq -n --arg model "$model" --arg msg "$msg" '{
        model: $model,
        messages: [{role: "user", content: $msg}],
        temperature: 0,
        max_tokens: 10,
        stream: false
    }'
}

invoke_preflight() {
    local name="$1" port="$2" model="$3" suffix="$4" path="$5" auth="${6:-}"
    local url="http://127.0.0.1:$port/$suffix/$path"
    local body
    body=$(new_chat_body "$model" "ping")
    echo -n "  Preflight $name... "
    local code
    code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $auth" \
        -d "$body" 2>/dev/null || echo "000")
    if [ "$code" = "000" ]; then
        echo "FAILED (no response)"
        return 1
    else
        echo "OK (HTTP $code)"
        return 0
    fi
}

invoke_warmup() {
    local port="$1" suffix="$2" path="$3" model="$4" auth="$5" count="${6:-5}"
    local url="http://127.0.0.1:$port/$suffix/$path"
    echo -n "  Warmup $count serial requests... "
    for i in $(seq 1 "$count"); do
        body=$(new_chat_body "$model" "warmup-$i")
        curl -sf -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $auth" \
            -d "$body" -o /dev/null 2>/dev/null || true
    done
    echo "done"
}

stop_processes_on_port() {
    for port in "$@"; do
        lsof -ti tcp:"$port" 2>/dev/null | xargs kill -9 2>/dev/null || true
    done
}

stop_bench_processes() {
    stop_processes_on_port 9099 8080 8081 8082 8090 8091 8585 8787 8000 9080 3001
}

build_bench_cli() {
    local bench_dir="$1"
    local cli_out="$bench_dir/bin/darwin/aurora-bench-cli"
    if [ -f "$cli_out" ]; then
        echo "$cli_out"
        return 0
    fi
    echo "  Building benchmark CLI..." >&2
    mkdir -p "$bench_dir/bin/darwin"
    (cd "$bench_dir" && go build -o "$cli_out" ./tools/benchmark-cli) >/dev/null 2>&1
    echo "$cli_out"
}

start_gateway_process() {
    local cmd="$1" log_path="$2"
    nohup $cmd > "$log_path" 2>&1 &
    echo $!
}
