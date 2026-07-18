# HOW TO ADD A NEW COMPETITOR (Linux)
# =====================================
# 1. Copy this file to competitors/NAME.sh
# 2. Fill in the variables and functions below
#
# Variables to set:
#   COMPETITOR_NAME          - short identifier (used as filename prefix, CLI arg)
#   COMPETITOR_DISPLAY_NAME  - human-readable name for reports
#   COMPETITOR_LANGUAGE       - Go, Python, Rust, TypeScript, etc.
#   COMPETITOR_PORT           - port the gateway listens on
#   COMPETITOR_HEALTH_PATH    - path for health check (e.g. "health")
#   COMPETITOR_HEALTH_TIMEOUT - max wait for gateway to become healthy (seconds)
#   COMPETITOR_PREFLIGHT_SUFFIX - URL prefix (e.g. "v1")
#   COMPETITOR_PREFLIGHT_PATH   - API path for preflight check (e.g. "chat/completions")
#   COMPETITOR_PREFLIGHT_MODEL  - model name for preflight request
#   COMPETITOR_TYPE             - installation type (binary, docker, pip, npm)
#
# Functions to define:
#   competitor_install()    - install/find binary, returns EXE path
#   competitor_start()      - start gateway, returns PID
#
# Available globals:
#   $BENCH_DIR  - root of bench repo
#   $REPO_ROOT  - same as BENCH_DIR
#   $MOCK_URL   - mock server URL (e.g. http://127.0.0.1:9099)
#   $API_KEY    - auth token for all gateways
#   $RESULTS_DIR - directory for benchmark results

COMPETITOR_NAME="example"
COMPETITOR_DISPLAY_NAME="Example Gateway"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8090
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_install() {
    local exe_path="$BENCH_DIR/bin/linux/example-gateway"
    if [ ! -f "$exe_path" ]; then
        echo "  Installing Example Gateway..."
        return 1
    fi
    echo "$exe_path"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local extra_args=()

    # Set environment variables
    export PORT="$port"
    export API_KEY="$API_KEY"
    export UPSTREAM_URL="$MOCK_URL"

    # Start process
    "$exe_path" "${extra_args[@]}" > "$RESULTS_DIR/example-server.log" 2>"$RESULTS_DIR/example-server.log.err" &
    echo $!
}
