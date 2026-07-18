COMPETITOR_NAME="new-api"
COMPETITOR_DISPLAY_NAME="New API"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=3001
COMPETITOR_HEALTH_PATH="api/status"
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="docker"
NEW_API_AUTH_TOKEN="$(openssl rand -hex 24)"
COMPETITOR_PREFLIGHT_AUTH="$NEW_API_AUTH_TOKEN"

competitor_install() {
    if ! command -v docker &>/dev/null; then
        echo "  ERROR: Docker not found." >&2
        return 1
    fi
    echo "  New API via Docker (calciumion/new-api)..." >&2
    echo "docker"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local mock_port
    mock_port=$(echo "$MOCK_URL" | sed 's/.*://')
    local data_dir="$RESULTS_DIR/new-api-data"
    local init_flag="$data_dir/initialized.flag"
    mkdir -p "$data_dir"

    docker rm -f new-api-bench new-api-init 2>/dev/null

    if [ ! -f "$init_flag" ]; then
        echo "  Initializing New API database..." >&2
        docker run -d --rm --name new-api-init --add-host host.docker.internal:host-gateway -p 3002:3000 \
            -e SESSION_SECRET="bench-bench-bench" \
            -e GENERATE_DEFAULT_TOKEN=true \
            calciumion/new-api:latest > /dev/null 2>&1

        local init_ready=false
        for i in $(seq 1 30); do
            sleep 1
            if curl -sf "http://127.0.0.1:3002/api/status" > /dev/null 2>&1; then
                init_ready=true
                break
            fi
        done

        if [ "$init_ready" = false ]; then
            echo "  ERROR: New API init container did not become ready" >&2
            return 1
        fi

        curl -sf -X POST "http://127.0.0.1:3002/api/user/register" \
            -H "Content-Type: application/json" \
            -d '{"username":"root","password":"adminadmin"}' > /dev/null 2>&1
        sleep 2

        docker cp new-api-init:/data/one-api.db "$data_dir/" 2>/dev/null
        docker stop new-api-init > /dev/null 2>&1

        local user_group
        user_group=$(docker run --rm -v "$data_dir:/data" alpine:latest sh -c "
            apk add sqlite-libs sqlite > /dev/null 2>&1
            sqlite3 /data/one-api.db \"SELECT [group] FROM users WHERE id = 1;\"
        ")

        local ts
        ts=$(date +%s)

        docker run --rm -v "$data_dir:/data" alpine:latest sh -c "
            apk add sqlite-libs sqlite > /dev/null 2>&1
            sqlite3 /data/one-api.db \"UPDATE users SET role = 100, quota = 100000000 WHERE id = 1;\"
            sqlite3 /data/one-api.db \"INSERT INTO channels (type, key, status, name, weight, created_time, base_url, models, [group], auto_ban) VALUES (1, 'sk-mock-key', 1, 'Mock OpenAI', 0, $ts, 'http://host.docker.internal:${mock_port}', 'gpt-4o-mini', '$user_group', 1);\"
            sqlite3 /data/one-api.db \"INSERT INTO abilities ([group], model, channel_id, enabled, priority, weight) VALUES ('$user_group', 'gpt-4o-mini', 1, 1, 0, 0);\"
            sqlite3 /data/one-api.db \"INSERT INTO tokens (user_id, key, status, name, created_time, accessed_time, remain_quota, unlimited_quota) VALUES (1, '$NEW_API_AUTH_TOKEN', 1, 'bench-token', $ts, $ts, 500000, 1);\"
        " 2>&1

        touch "$init_flag"
        echo "  New API database initialized" >&2
    fi

    docker run -d --rm --name new-api-bench --add-host host.docker.internal:host-gateway \
        --log-driver none \
        -p "${port}:3000" \
        -v "$data_dir:/data" \
        -e ERROR_LOG_ENABLED=false \
        -e SESSION_SECRET="bench-bench-bench" \
        -e GENERATE_DEFAULT_TOKEN=true \
        calciumion/new-api:latest > /dev/null 2>&1

    local container_id
    container_id=$(docker ps -q -f name=new-api-bench)
    if [ -n "$container_id" ]; then
        docker inspect "$container_id" | jq -r '.[0].State.Pid'
    else
        echo ""
    fi
}
