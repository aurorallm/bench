COMPETITOR_NAME="helicone"
COMPETITOR_DISPLAY_NAME="Helicone AI Gateway (Docker)"
COMPETITOR_LANGUAGE="Rust"
COMPETITOR_PORT=8585
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="openai"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_BENCHMARK_PATH="openai/chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="docker"

competitor_install() {
    if ! command -v docker &>/dev/null; then
        echo "  ERROR: Docker not found." >&2
        return 1
    fi
    echo "  Helicone via Docker (helicone/ai-gateway)..." >&2
    echo "docker"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local mock_port
    mock_port=$(echo "$MOCK_URL" | sed 's/.*://')
    local config_path="$RESULTS_DIR/helicone.yaml"

    cat > "$config_path" << CFGEOF
providers:
  openai:
    models:
      - "gpt-4o-mini"
    base-url: "http://host.docker.internal:${mock_port}/v1"
CFGEOF

    docker rm -f helicone-bench 2>/dev/null

    docker run -d --rm --name helicone-bench --add-host host.docker.internal:host-gateway \
        --log-driver none \
        -p "${port}:8080" \
        -e OPENAI_API_KEY="$API_KEY" \
        -e RUST_LOG=off \
        -v "${config_path}:/app/config.yaml" \
        helicone/ai-gateway:latest \
        /usr/local/bin/ai-gateway --config /app/config.yaml > /dev/null 2>&1

    local container_id
    container_id=$(docker ps -q -f name=helicone-bench)
    if [ -n "$container_id" ]; then
        docker inspect "$container_id" | jq -r '.[0].State.Pid'
    else
        echo ""
    fi
}
