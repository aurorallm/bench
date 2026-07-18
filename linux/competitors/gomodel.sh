COMPETITOR_NAME="gomodel"
COMPETITOR_DISPLAY_NAME="GoModel AI Gateway (Docker)"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8091
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="docker"

competitor_install() {
    if ! command -v docker &>/dev/null; then
        echo "  ERROR: Docker not found." >&2
        return 1
    fi
    echo "  GoModel via Docker (enterpilot/gomodel)..." >&2
    echo "docker"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local mock_port
    mock_port=$(echo "$MOCK_URL" | sed 's/.*://')

    docker rm -f gomodel-bench 2>/dev/null

    docker run -d --rm --name gomodel-bench --add-host host.docker.internal:host-gateway \
        --log-driver none \
        -p "${port}:8080" \
        -e GOMODEL_MASTER_KEY="$API_KEY" \
        -e OPENAI_API_KEY="$API_KEY" \
        -e OPENAI_BASE_URL="http://host.docker.internal:${mock_port}/v1" \
        -e LOGGING_ENABLED=false \
        -e USAGE_ENABLED=false \
        -e ADMIN_ENDPOINTS_ENABLED=false \
        -e ADMIN_UI_ENABLED=false \
        -e GUARDRAILS_ENABLED=false \
        -e SWAGGER_ENABLED=false \
        -e PPROF_ENABLED=false \
        -e CLI_TOOLS_ENABLED=false \
        -e COMBOS_ENABLED=false \
        -e METRICS_ENABLED=false \
        -e RESPONSE_CACHE_SIMPLE_ENABLED=false \
        -e SEMANTIC_CACHE_ENABLED=false \
        -e TOKEN_SAVER_ENABLED=false \
        enterpilot/gomodel:latest > /dev/null 2>&1

    local container_id
    container_id=$(docker ps -q -f name=gomodel-bench)
    if [ -n "$container_id" ]; then
        docker inspect "$container_id" | jq -r '.[0].State.Pid'
    else
        echo ""
    fi
}
