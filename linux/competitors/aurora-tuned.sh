COMPETITOR_NAME="aurora-tuned"
COMPETITOR_DISPLAY_NAME="Aurora Gateway (tuned)"
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
    local log_path="$RESULTS_DIR/aurora-tuned-server.log"

    export PORT="$port"
    export OPENAI_BASE_URL="$MOCK_URL"
    export OPENAI_API_KEY="$API_KEY"
    export AURORA_MASTER_KEY="$API_KEY"
    export AURORA_MINIMAL_BENCH_MODE="true"
    export AURORA_H2C_ENABLED="true"
    export AURORA_CHAT_FAST_PATH_PASSTHROUGH="true"
    export HTTP_MAX_IDLE_CONNS="4096"
    export HTTP_MAX_IDLE_CONNS_PER_HOST="4096"
    export HTTP_MAX_CONNS_PER_HOST="256"
    export MODEL_LIST_URL=""
    export STORAGE_TYPE="sqlite"
    export IDENTITY_ENABLED="false"
    export GUARDRAILS_ENABLED="false"
    export USAGE_ENABLED="false"
    export LOGGING_ENABLED="false"
    export METRICS_ENABLED="false"
    export SEMANTIC_CACHE_ENABLED="false"
    export RESPONSE_CACHE_SIMPLE_ENABLED="false"
    export TOKEN_SAVER_ENABLED="false"
    export PROMPT_CACHE_MODE="off"
    export SWAGGER_ENABLED="false"
    export ENABLE_ANTHROPIC_INGRESS="false"
    export CLI_TOOLS_ENABLED="false"
    export COMBOS_ENABLED="false"
    export ADMIN_ENDPOINTS_ENABLED="false"
    export ADMIN_UI_ENABLED="false"

    "$exe_path" > "$log_path" 2>"${log_path}.err" &
    echo $!
}
