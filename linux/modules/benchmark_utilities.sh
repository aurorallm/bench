# Linux Benchmark Utilities
# Bash equivalents of BenchmarkUtilities.psm1

wait_for_health() {
    local name="$1"
    local port="$2"
    local timeout="${3:-30}"
    local health_path="${4:-health}"
    local check_type="${5:-http}"
    local deadline=$(( $(date +%s) + timeout ))

    if [ "$check_type" = "tcp" ]; then
        while [ $(date +%s) -lt $deadline ]; do
            if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
                echo "  $name TCP health check OK (port $port)"
                return 0
            fi
            sleep 0.5
        done
        echo "ERROR: $name did not become healthy on port $port within ${timeout}s (TCP)"
        return 1
    fi

    local url="http://127.0.0.1:$port/$health_path"
    while [ $(date +%s) -lt $deadline ]; do
        if curl -sf --max-time 2 "$url" > /dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    echo "ERROR: $name did not become healthy on port $port within ${timeout}s"
    return 1
}

new_chat_body() {
    local model="${1:-gpt-4o-mini}"
    printf '{"model":"%s","messages":[{"role":"user","content":"benchmark preflight"}]}' "$model"
}

invoke_preflight() {
    local name="$1"
    local port="$2"
    local model="${3:-gpt-4o-mini}"
    local suffix="${4-v1}"
    local path="${5-chat/completions}"
    local auth_token="${6-sk-bench-test-key}"
    local extra_headers="${7-}"

    local url="http://127.0.0.1:$port"
    [ -n "$suffix" ] && url+="/$suffix"
    url+="/$path"
    local body
    body=$(new_chat_body "$model")

    local curl_args=()
    [ -n "$extra_headers" ] && while IFS='|' read -ra hdrs; do
        for h in "${hdrs[@]}"; do
            [ -n "$h" ] && curl_args+=(-H "$h")
        done
    done <<< "$extra_headers"

    for i in $(seq 1 12); do
        if curl -sf -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $auth_token" \
            "${curl_args[@]}" \
            -d "$body" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "^2"; then
            echo "  $name preflight OK (HTTP 2xx)"
            return 0
        fi
        sleep 2.5
    done
    echo "ERROR: $name preflight failed at $url after 12 retries"
    return 1
}

invoke_warmup() {
    local name="$1"
    local port="$2"
    local warmup_requests="${3:-25}"
    local model="${4:-gpt-4o-mini}"
    local suffix="${5-v1}"
    local path="${6-chat/completions}"
    local auth_token="${7-sk-bench-test-key}"

    [ "$warmup_requests" -le 0 ] && return 0

    local url="http://127.0.0.1:$port"
    [ -n "$suffix" ] && url+="/$suffix"
    url+="/$path"
    local body
    body=$(new_chat_body "$model")

    for i in $(seq 1 $warmup_requests); do
        if ! curl -sf -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $auth_token" \
            -d "$body" -o /dev/null 2>/dev/null; then
            echo "ERROR: $name warmup failed at request $i"
            return 1
        fi
    done
    echo "  $name warmup: $warmup_requests requests"
    return 0
}

stop_processes_on_port() {
    local ports=("$@")
    for port in "${ports[@]}"; do
        local pids
        pids=$(lsof -ti :"$port" 2>/dev/null || fuser "$port/tcp" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                local pname
                pname=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                if echo "$pname" | grep -qiE "docker|com\.docker"; then
                    continue
                fi
                kill -9 "$pid" 2>/dev/null && echo "  Killed process $pid ($pname) on port $port" || true
            done
        fi
    done
}

stop_bench_processes() {
    local ports=("${@:-8080 8081 9099}")
    local names=("mock-server" "aurora-bench" "bifrost-http" "aurora-bench-cli" "k6")
    for name in "${names[@]}"; do
        pkill -9 "$name" 2>/dev/null && echo "  Killed all $name processes"
    done
    stop_processes_on_port "${ports[@]}"
}

build_bench_cli() {
    local bench_dir="$1"
    local bin_dir="$bench_dir/bin/linux"
    local cli_src="$bench_dir/tools/benchmark-cli"
    local output="$bin_dir/aurora-bench-cli"

    [ ! -f "$cli_src/main.go" ] && echo "ERROR: Benchmark CLI source not found at $cli_src" && return 1

    mkdir -p "$bin_dir"

    if [ -f "$output" ]; then
        local newer
        newer=$(find "$cli_src" -name "*.go" -newer "$output" 2>/dev/null | head -1)
        [ -z "$newer" ] && echo "$output" && return 0
        echo "Benchmark CLI source changed, rebuilding..." >&2
    fi

    echo "Building benchmark CLI..." >&2
    (cd "$bench_dir" && GOOS=linux GOARCH=amd64 go build -o "$output" "$cli_src") || return 1
    echo "Benchmark CLI built: $output" >&2
    echo "$output"
}

start_gateway_process() {
    local exe_path="$1"
    shift
    local env_vars=()
    local extra_args=()
    local log_path=""
    local working_dir=""
    local nohup=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --env) shift; env_vars+=("$1") ;;
            --arg) shift; extra_args+=("$1") ;;
            --log) shift; log_path="$1" ;;
            --workdir) shift; working_dir="$1" ;;
            --nohup) nohup=true ;;
        esac
        shift
    done

    for env_var in "${env_vars[@]}"; do
        export "$env_var"
    done

    local cmd=("$exe_path" "${extra_args[@]}")

    if [ -n "$log_path" ]; then
        if $nohup; then
            nohup "${cmd[@]}" > "$log_path" 2>"${log_path}.err" &
        else
            "${cmd[@]}" > "$log_path" 2>"${log_path}.err" &
        fi
    else
        if $nohup; then
            nohup "${cmd[@]}" > /dev/null 2>&1 &
        else
            "${cmd[@]}" > /dev/null 2>&1 &
        fi
    fi

    echo $!
}
