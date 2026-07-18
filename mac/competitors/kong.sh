COMPETITOR_NAME="kong"
COMPETITOR_DISPLAY_NAME="Kong AI Gateway"
COMPETITOR_LANGUAGE="Lua/Nginx"
COMPETITOR_PORT=8000
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="docker"

competitor_health_check_type() { echo "tcp"; }

competitor_install() {
    if ! command -v docker &>/dev/null; then
        echo "  ERROR: Docker not found."
        return 1
    fi
    echo "  Kong via Docker (kong:latest)..."
    echo "docker"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local mock_port
    mock_port=$(echo "$MOCK_URL" | sed 's/.*://')
    local template_path="$BENCH_DIR/configs/kong-bench.yaml"

    local config_content
    config_content=$(sed "s/MOCK_PORT/$mock_port/g" "$template_path")
    local config_path="$RESULTS_DIR/kong.yaml"
    echo "$config_content" > "$config_path"

    docker rm -f kong-bench 2>/dev/null

    docker run -d --rm --name kong-bench \
        --log-driver none \
        -p "${port}:8000" \
        -e KONG_DATABASE=off \
        -e KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml \
        -e KONG_PROXY_ACCESS_LOG=/dev/null \
        -e KONG_PROXY_ERROR_LOG=/dev/null \
        -e KONG_LOG_LEVEL=crit \
        -e KONG_PLUGINS=cors \
        -e KONG_ADMIN_LISTEN=off \
        -e KONG_ADMIN_ACCESS_LOG=off \
        -e KONG_ADMIN_ERROR_LOG=/dev/null \
        -e KONG_STATUS_ACCESS_LOG=off \
        -e KONG_STATUS_ERROR_LOG=/dev/null \
        -v "${config_path}:/kong/declarative/kong.yml" \
        kong:latest > /dev/null 2>&1

    local container_id
    container_id=$(docker ps -q -f name=kong-bench)
    if [ -n "$container_id" ]; then
        docker inspect "$container_id" | jq -r '.[0].State.Pid'
    else
        echo ""
    fi
}
