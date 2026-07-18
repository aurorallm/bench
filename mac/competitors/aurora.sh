COMPETITOR_NAME="aurora"
COMPETITOR_DISPLAY_NAME="Aurora Gateway"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8081
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_install() {
    local aurora_exe="$BENCH_DIR/bin/darwin/aurora-bench"
    if [ -f "$aurora_exe" ]; then
        echo "$aurora_exe"
        return 0
    fi

    echo "  Aurora binary not found. Downloading from GitHub releases..."
    local bin_dir="$BENCH_DIR/bin/darwin"
    mkdir -p "$bin_dir"

    local arch
    arch=$(uname -m)
    [ "$arch" = "x86_64" ] && arch="amd64"
    [ "$arch" = "aarch64" ] && arch="arm64"

    echo "  Looking up latest Aurora release..."
    local release
    release=$(curl -sf "https://api.github.com/repos/aurorallm/aurora/releases/latest" 2>/dev/null) || {
        echo "  ERROR: Failed to fetch release info"
        return 1
    }

    local tag
    tag=$(echo "$release" | jq -r '.tag_name')
    echo "  Latest release: $tag"

    local asset_filter="darwin_${arch}\\.tar\\.gz$"
    local asset_name
    asset_name=$(echo "$release" | jq -r --arg arch "$arch" '.assets[] | select(.name | test("darwin_"+$arch+"\\.tar\\.gz$")) | .name' | head -1)
    if [ -z "$asset_name" ]; then
        asset_name=$(echo "$release" | jq -r '.assets[] | select(.name | test("darwin_amd64\\.tar\\.gz$")) | .name' | head -1)
    fi
    [ -z "$asset_name" ] && echo "  ERROR: No darwin tar.gz asset found" && return 1

    local download_url="https://github.com/aurorallm/aurora/releases/download/$tag/$asset_name"
    local tar_path="$bin_dir/aurora.tar.gz"

    echo "  Downloading: $asset_name"
    curl -fL "$download_url" -o "$tar_path" || return 1

    echo "  Extracting..."
    tar -xzf "$tar_path" -C "$bin_dir" 2>/dev/null
    rm -f "$tar_path"

    local extracted
    extracted=$(find "$bin_dir" -maxdepth 1 -type f -name "aurora" 2>/dev/null | head -1)
    [ -z "$extracted" ] && echo "  ERROR: No aurora binary found in archive" && return 1

    [ "$extracted" != "$aurora_exe" ] && mv "$extracted" "$aurora_exe"
    chmod +x "$aurora_exe"

    local size
    size=$(du -h "$aurora_exe" 2>/dev/null | cut -f1)
    echo "  Aurora extracted: $aurora_exe ($size)"
    echo "$aurora_exe"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local log_path="$RESULTS_DIR/aurora-server.log"
    local bench_work_dir="$RESULTS_DIR/aurora-workdir"
    mkdir -p "$bench_work_dir"

    export PORT="$port"
    export OPENAI_BASE_URL="$MOCK_URL"
    export OPENAI_API_KEY="$API_KEY"
    export AURORA_MASTER_KEY="$API_KEY"
    export AURORA_MINIMAL_BENCH_MODE="true"
    export AURORA_H2C_ENABLED="true"
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
    export SWAGGER_ENABLED="false"
    export PPROF_ENABLED="false"
    export ENABLE_ANTHROPIC_INGRESS="false"
    export CLI_TOOLS_ENABLED="false"
    export COMBOS_ENABLED="false"
    export ADMIN_ENDPOINTS_ENABLED="false"
    export ADMIN_UI_ENABLED="false"

    cd "$bench_work_dir" && "$exe_path" > "$log_path" 2>"${log_path}.err" &
    echo $!
}
