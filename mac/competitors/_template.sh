# Template for macOS competitor definition
# Copy this file and rename to <competitor-name>.sh
# Override the variables and functions below.

COMPETITOR_NAME="my-gateway"
COMPETITOR_DISPLAY_NAME="My Gateway"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8090
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
# COMPETITOR_BENCHMARK_PATH="v1/chat/completions"  # overrides auto-join of suffix/path
# COMPETITOR_TYPE="binary|docker|npm|pip"

# competitor_install: outputs path to executable (or "docker"/"npm"/"pip")
competitor_install() {
    echo "  ERROR: implement competitor_install" >&2
    return 1
}

# competitor_start: outputs PID of started process
competitor_start() {
    local exe_path="$1"
    local port="$2"
    # start the gateway, return its PID
    echo "0"
}

# Optional: override health check type (default: "http", alternative: "tcp")
competitor_health_check_type() {
    echo "http"
}
