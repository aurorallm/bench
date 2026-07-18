COMPETITOR_NAME="axonhub"
COMPETITOR_DISPLAY_NAME="AxonHub Gateway"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8090
COMPETITOR_HEALTH_PATH="admin/system/status"
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

AXONHUB_TAG="v1.0.0-beta5"

competitor_install() {
    local exe_path="$BENCH_DIR/bin/linux/axonhub"
    if [ -f "$exe_path" ]; then
        local size
        size=$(du -h "$exe_path" 2>/dev/null | cut -f1)
        echo "  AxonHub binary: $exe_path ($size)" >&2
        echo "$exe_path"
        return 0
    fi

    echo "  AxonHub binary not found. Downloading from GitHub releases..." >&2
    local bin_dir="$BENCH_DIR/bin/linux"
    mkdir -p "$bin_dir"

    local tag="$AXONHUB_TAG"
    local zip_name="axonhub_${tag#v}_linux_amd64.zip"
    local download_url="https://github.com/looplj/axonhub/releases/download/$tag/$zip_name"
    local zip_path="$bin_dir/axonhub.zip"

    echo "  Downloading: $zip_name" >&2
    curl -fL "$download_url" -o "$zip_path" || { echo "  ERROR: Download failed" >&2; return 1; }

    echo "  Extracting..." >&2
    local extract_dir="$bin_dir/axonhub-extract"
    mkdir -p "$extract_dir"
    if command -v unzip &>/dev/null; then
        unzip -o "$zip_path" -d "$extract_dir" > /dev/null 2>&1
    else
        python3 -c "import zipfile, sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$zip_path" "$extract_dir" 2>/dev/null
    fi
    rm -f "$zip_path"

    local extracted
    extracted=$(find "$extract_dir" -maxdepth 2 -name "axonhub" -type f 2>/dev/null | head -1)
    if [ -z "$extracted" ]; then
        echo "  ERROR: No axonhub binary found in archive" >&2
        rm -rf "$extract_dir"
        return 1
    fi

    mv "$extracted" "$exe_path"
    chmod +x "$exe_path"
    rm -rf "$extract_dir"

    local size
    size=$(du -h "$exe_path" 2>/dev/null | cut -f1)
    echo "  AxonHub downloaded: $exe_path ($size)" >&2
    echo "$exe_path"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local log_path="$RESULTS_DIR/axonhub-server.log"
    local bench_work_dir="$RESULTS_DIR/axonhub-workdir"
    mkdir -p "$bench_work_dir"

    export AXONHUB_SERVER_PORT="$port"
    export AXONHUB_SERVER_DEBUG="false"
    export AXONHUB_SERVER_REQUEST_TIMEOUT="60s"
    export AXONHUB_SERVER_LLM_REQUEST_TIMEOUT="60s"
    export AXONHUB_SERVER_API_AUTH_ALLOW_NO_AUTH="true"
    export AXONHUB_LOG_LEVEL="fatal"
    export AXONHUB_LOG_ENCODING="console"
    export AXONHUB_LOG_OUTPUT="stdio"
    export AXONHUB_METRICS_ENABLED="false"
    export AXONHUB_DB_DIALECT="sqlite3"
    export AXONHUB_DB_MAX_OPEN_CONNS="5"
    export AXONHUB_DB_MAX_IDLE_CONNS="2"
    export AXONHUB_CACHE_MODE="memory"
    export AXONHUB_GC_CRON=""
    export AXONHUB_PROVIDER_QUOTA_CHECK_INTERVAL="24h"

    local old_pwd="$PWD"
    cd "$bench_work_dir" && "$exe_path" > "$log_path" 2>"${log_path}.err" &
    local pid=$!
    cd "$old_pwd" 2>/dev/null || true

    local base_url="http://127.0.0.1:$port"
    local ready=false
    for i in $(seq 1 30); do
        sleep 1
        if curl -sf "$base_url/admin/system/status" > /dev/null 2>&1; then
            ready=true; break
        fi
    done
    if [ "$ready" = false ]; then
        echo "  ERROR: AxonHub did not start on port $port" >&2
        kill "$pid" 2>/dev/null || true
        return 1
    fi
    echo "  AxonHub started (PID: $pid)" >&2

    local init_flag="$bench_work_dir/initialized.flag"
    if [ ! -f "$init_flag" ]; then
        echo "  Initializing AxonHub system..." >&2

        local status
        status=$(curl -sf "$base_url/admin/system/status" 2>/dev/null)
        local is_init
        is_init=$(echo "$status" | jq -r '.isInitialized // false' 2>/dev/null)

        if [ "$is_init" != "true" ]; then
            curl -sf -X POST "$base_url/admin/system/initialize" \
                -H "Content-Type: application/json" \
                -d '{"ownerEmail":"bench@axonhub.local","ownerPassword":"benchbench123","ownerFirstName":"Bench","ownerLastName":"User","brandName":"AxonHub Bench"}' > /dev/null 2>&1
            sleep 2
            echo "  System initialized" >&2
        fi

        echo "  Signing in..." >&2
        local login_resp
        login_resp=$(curl -sf -X POST "$base_url/admin/auth/signin" \
            -H "Content-Type: application/json" \
            -d '{"email":"bench@axonhub.local","password":"benchbench123"}' 2>/dev/null) || {
            echo "  WARNING: Sign-in failed (may already have token)" >&2
        }

        if [ -n "$login_resp" ]; then
            local jwt_token
            jwt_token=$(echo "$login_resp" | jq -r '.token // empty' 2>/dev/null)
            if [ -n "$jwt_token" ]; then
                local auth="Authorization: Bearer $jwt_token"
                local mock_port
                mock_port=$(echo "$MOCK_URL" | sed 's/.*://')

                echo "  Creating channel to mock server (port $mock_port)..." >&2
                local channel_resp
                channel_resp=$(curl -sf -X POST "$base_url/admin/graphql" \
                    -H "Content-Type: application/json" \
                    -H "$auth" \
                    -d "{\"query\":\"mutation { createChannel(input: {type: openai, baseURL: \\\"http://127.0.0.1:$mock_port\\\", name: \\\"Mock Server\\\", credentials: {apiKey: \\\"sk-mock-key\\\"}, supportedModels: [\\\"gpt-4o-mini\\\"], defaultTestModel: \\\"gpt-4o-mini\\\"}) { id name status } }\"}" 2>/dev/null)
                local channel_id
                channel_id=$(echo "$channel_resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('createChannel',{}).get('id',''))" 2>/dev/null)
                if [ -n "$channel_id" ]; then
                    echo "  Channel created: $channel_id" >&2
                    curl -sf -X POST "$base_url/admin/graphql" \
                        -H "Content-Type: application/json" \
                        -H "$auth" \
                        -d "{\"query\":\"mutation { updateChannelStatus(id: \\\"$channel_id\\\", status: enabled) { id name status } }\"}" > /dev/null 2>&1
                    echo "  Channel enabled" >&2
                else
                    echo "  Channel may already exist" >&2
                fi
                sleep 1
            fi
        fi

        echo "  Disabling background tasks..." >&2
        local gql_auth="Authorization: Bearer $jwt_token"
        local disable_mutations='{"query":"mutation { updateStoragePolicy(input: {storeRequestBody: false, storeResponseBody: false, storeChunks: false, livePreview: false}) }"}'
        curl -sf -X POST "$base_url/admin/graphql" \
            -H "Content-Type: application/json" \
            -H "$gql_auth" \
            -d "$disable_mutations" > /dev/null 2>&1
        curl -sf -X POST "$base_url/admin/graphql" \
            -H "Content-Type: application/json" \
            -H "$gql_auth" \
            -d '{"query":"mutation { updateSystemChannelSettings(input: {probe: {enabled: false, frequency: ONE_HOUR}, autoSync: {frequency: ONE_DAY}}) }"}' > /dev/null 2>&1
        curl -sf -X POST "$base_url/admin/graphql" \
            -H "Content-Type: application/json" \
            -H "$gql_auth" \
            -d '{"query":"mutation { updateRetryPolicy(input: {enabled: false, maxChannelRetries: 0, maxSingleChannelRetries: 0}) }"}' > /dev/null 2>&1
        curl -sf -X POST "$base_url/admin/graphql" \
            -H "Content-Type: application/json" \
            -H "$gql_auth" \
            -d '{"query":"mutation { completeOnboarding(input: {dummy: \"\"}) }"}' > /dev/null 2>&1
        echo "  Background tasks disabled" >&2

        touch "$init_flag"
        echo "  AxonHub initialization complete" >&2
    else
        echo "  Using previously initialized AxonHub" >&2
    fi

    echo "$pid"
}
