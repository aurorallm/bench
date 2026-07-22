COMPETITOR_NAME="aurora-default"
COMPETITOR_DISPLAY_NAME="Aurora Gateway (default)"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8081
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_install() {
    local aurora_exe="$BENCH_DIR/bin/linux/aurora-bench"
    if [ -f "$aurora_exe" ]; then
        echo "$aurora_exe"
        return 0
    fi
    echo "  Aurora binary not found. Run 'aurora' competitor first to download it." >&2
    return 1
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local log_path="$RESULTS_DIR/aurora-default-server.log"

    export PORT="$port"
    export OPENAI_BASE_URL="$MOCK_URL"
    export OPENAI_API_KEY="$API_KEY"
    export AURORA_MASTER_KEY="$API_KEY"

    # Pure out-of-the-box defaults — no tuning env vars.
    # Code defaults are already bench-optimized:
    #   h2c always-on, HTTP_MAX_IDLE_CONNS=4096,
    #   HTTP_MAX_CONNS_PER_HOST=256, PROMPT_CACHE_MODE=off,
    #   all non-essential features disabled by default.

    "$exe_path" > "$log_path" 2>"${log_path}.err" &
    echo $!
}
