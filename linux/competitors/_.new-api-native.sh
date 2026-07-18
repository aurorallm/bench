COMPETITOR_NAME="new-api-native"
COMPETITOR_DISPLAY_NAME="New API (Native)"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=3001
COMPETITOR_HEALTH_PATH="api/status"
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_install() {
    local newapi_exe="$BENCH_DIR/bin/linux/new-api"
    if [ -f "$newapi_exe" ]; then
        local size
        size=$(du -h "$newapi_exe" 2>/dev/null | cut -f1)
        echo "  New API native binary: $newapi_exe ($size)" >&2
        echo "$newapi_exe"
        return 0
    fi

    echo "  New API binary not found. Downloading from GitHub releases..." >&2
    local bin_dir="$BENCH_DIR/bin/linux"
    mkdir -p "$bin_dir"

    local tag asset_name tar_path="$bin_dir/new-api.tar.gz"

    if command -v gh &>/dev/null; then
        echo "  Looking up latest New API release via gh..." >&2
        tag=$(gh release list -R QuantumNous/new-api --json tagName -q '.[0].tagName' 2>/dev/null) || {
            echo "  ERROR: Failed to fetch release info via gh" >&2
            return 1
        }
        echo "  Latest release: $tag" >&2
        asset_name=$(gh release view "$tag" -R QuantumNous/new-api --json assets -q '.assets[] | select(.name | contains("new-api-v")) | select(.name | contains("arm64") | not) | select(.name | contains("macos") | not) | select(.name | contains(".exe") | not) | .name' 2>/dev/null | head -1)
        [ -z "$asset_name" ] && echo "  ERROR: No Linux amd64 binary asset found" && return 1

        echo "  Downloading: $asset_name" >&2
        gh release download "$tag" -R QuantumNous/new-api -p "$asset_name" -O "$tar_path" || return 1
    else
        echo "  Looking up latest New API release via curl..." >&2
        local release
        release=$(curl -sf "https://api.github.com/repos/QuantumNous/new-api/releases/latest" 2>/dev/null) || {
            echo "  ERROR: Failed to fetch release info" >&2
            return 1
        }

        tag=$(echo "$release" | jq -r '.tag_name')
        echo "  Latest release: $tag" >&2
        asset_name=$(echo "$release" | jq -r '.assets[] | select(.name | contains("new-api-v")) | select(.name | contains("arm64") | not) | select(.name | contains("macos") | not) | select(.name | contains(".exe") | not) | .name' | head -1)
        [ -z "$asset_name" ] && echo "  ERROR: No Linux amd64 binary asset found" && return 1

        local download_url="https://github.com/QuantumNous/new-api/releases/download/$tag/$asset_name"
        echo "  Downloading: $asset_name" >&2
        curl -fL "$download_url" -o "$tar_path" || return 1
    fi
    mv "$tar_path" "$newapi_exe" 2>/dev/null
    chmod +x "$newapi_exe"
    local size
    size=$(du -h "$newapi_exe" 2>/dev/null | cut -f1)
    echo "  New API downloaded: $newapi_exe ($size)" >&2
    echo "$newapi_exe"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local log_dir="$RESULTS_DIR/new-api-logs"
    local data_dir="$RESULTS_DIR/new-api-data"
    mkdir -p "$log_dir" "$data_dir"

    export ERROR_LOG_ENABLED="false"
    export MEMORY_CACHE_ENABLED="true"
    export GENERATE_DEFAULT_TOKEN="true"
    export SESSION_SECRET="bench-bench-bench"
    export BATCH_UPDATE_ENABLED="false"
    export GIN_MODE="release"

    "$exe_path" --port "$port" --log-dir "$log_dir" > "$log_dir/server.log" 2>&1 &
    local pid=$!

    local base_url="http://127.0.0.1:$port"
    local ready=false
    for i in $(seq 1 30); do
        sleep 1
        if curl -sf "$base_url/api/status" > /dev/null 2>&1; then
            ready=true; break
        fi
    done

    if [ "$ready" = false ]; then
        echo "  ERROR: New API did not become ready on port $port" >&2
        kill "$pid" 2>/dev/null || true
        return 1
    fi

    local init_flag="$data_dir/initialized.flag"
    if [ ! -f "$init_flag" ]; then
        echo "  Initializing New API (admin, channel, token)..." >&2

        curl -sf -X POST "$base_url/api/user/register" \
            -H "Content-Type: application/json" \
            -d '{"username":"root","password":"adminadmin"}' > /dev/null 2>&1
        sleep 2

        local login_resp
        login_resp=$(curl -sf -X POST "$base_url/api/user/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"root","password":"adminadmin"}' 2>/dev/null)
        local session_token
        session_token=$(echo "$login_resp" | jq -r '.token' 2>/dev/null)
        local auth="Authorization: Bearer $session_token"

        local mock_port
        mock_port=$(echo "$MOCK_URL" | sed 's/.*://')

        curl -sf -X POST "$base_url/api/channel/" \
            -H "Content-Type: application/json" \
            -H "$auth" \
            -d "{\"type\":1,\"key\":\"sk-mock-key\",\"name\":\"Mock OpenAI\",\"base_url\":\"http://127.0.0.1:$mock_port\",\"models\":\"gpt-4o-mini\",\"weight\":0,\"auto_ban\":1}" > /dev/null 2>&1
        sleep 1

        curl -sf -X POST "$base_url/api/token/" \
            -H "Content-Type: application/json" \
            -H "$auth" \
            -d '{"name":"bench-token","remain_quota":500000,"unlimited_quota":false}' > /dev/null 2>&1
        sleep 1

        touch "$init_flag"
        echo "  New API initialized" >&2
    fi

    echo "$pid"
}
