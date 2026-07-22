COMPETITOR_NAME="aurora-docker"
COMPETITOR_DISPLAY_NAME="Aurora Gateway (Docker)"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8082
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
    echo "  Aurora via Docker (aurorahq/aurora)..." >&2
    echo "docker"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"

    local mock_port
    mock_port=$(echo "$MOCK_URL" | sed 's/.*://')

    docker rm -f aurora-docker-bench 2>/dev/null
    docker pull aurorahq/aurora:latest 2>/dev/null

    docker run -d --rm --name aurora-docker-bench --add-host host.docker.internal:host-gateway \
        --log-driver none \
        -p "${port}:8080" \
        --cap-drop=all \
        --security-opt seccomp=unconfined \
        --ulimit nofile=65535:65535 \
        --shm-size=256m \
        -e AURORA_MASTER_KEY="$API_KEY" \
        -e OPENAI_API_KEY="$API_KEY" \
        -e OPENAI_BASE_URL="http://host.docker.internal:${mock_port}" \
        -e AURORA_MINIMAL_BENCH_MODE=true \
        -e AURORA_CHAT_FAST_PATH_PASSTHROUGH=true \
        -e HTTP_MAX_CONNS_PER_HOST=256 \
        -e DISABLE_REQUEST_BODY_SNAPSHOT=true \
        -e DISABLE_PASSTHROUGH_SEMANTIC_ENRICHMENT=true \
        aurorahq/aurora:latest > /dev/null 2>&1

    local container_id
    container_id=$(docker ps -q -f name=aurora-docker-bench)
    if [ -n "$container_id" ]; then
        docker inspect "$container_id" | jq -r '.[0].State.Pid'
    else
        echo "  ERROR: Docker container failed to start" >&2
        echo ""
    fi
}
