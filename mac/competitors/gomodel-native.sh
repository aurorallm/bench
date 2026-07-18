COMPETITOR_NAME="gomodel-native"
COMPETITOR_DISPLAY_NAME="GoModel AI Gateway (Native)"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8091
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=15
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_install() {
    local gomodel_exe="$BENCH_DIR/bin/darwin/gomodel"
    if [ -f "$gomodel_exe" ]; then
        local size
        size=$(du -h "$gomodel_exe" 2>/dev/null | cut -f1)
        echo "  GoModel native binary found: $gomodel_exe ($size)"
        echo "$gomodel_exe"
        return 0
    fi

    echo "  GoModel binary not found. Downloading from GitHub releases..."
    local bin_dir="$BENCH_DIR/bin/darwin"
    mkdir -p "$bin_dir"

    echo "  Looking up latest GoModel release..."
    local release
    release=$(curl -sf "https://api.github.com/repos/ENTERPILOT/GoModel/releases/latest" 2>/dev/null) || {
        echo "  ERROR: Failed to fetch release info"
        return 1
    }

    local tag
    tag=$(echo "$release" | jq -r '.tag_name')
    echo "  Latest release: $tag"

    local arch
    arch=$(uname -m)
    [ "$arch" = "x86_64" ] && arch="amd64"
    [ "$arch" = "aarch64" ] && arch="arm64"

    local asset_name
    asset_name=$(echo "$release" | jq -r --arg arch "$arch" '.assets[] | select(.name | test("darwin_"+$arch+"\\.tar\\.gz$")) | .name' | head -1)

    if [ -z "$asset_name" ]; then
        asset_name=$(echo "$release" | jq -r '.assets[] | select(.name | test("darwin_amd64\\.tar\\.gz$")) | .name' | head -1)
    fi

    [ -z "$asset_name" ] && echo "  ERROR: No darwin tar.gz asset found" && return 1

    local download_url="https://github.com/ENTERPILOT/GoModel/releases/download/$tag/$asset_name"
    local tar_path="$bin_dir/gomodel.tar.gz"

    echo "  Downloading: $asset_name"
    curl -fL "$download_url" -o "$tar_path" || return 1

    echo "  Extracting..."
    tar -xzf "$tar_path" -C "$bin_dir" 2>/dev/null
    rm -f "$tar_path"

    local extracted
    extracted=$(find "$bin_dir" -maxdepth 1 -type f -name "gomodel" 2>/dev/null | head -1)
    [ -z "$extracted" ] && echo "  ERROR: No gomodel binary found in archive" && return 1

    [ "$extracted" != "$gomodel_exe" ] && mv "$extracted" "$gomodel_exe"
    chmod +x "$gomodel_exe"

    local size
    size=$(du -h "$gomodel_exe" 2>/dev/null | cut -f1)
    echo "  GoModel downloaded: $gomodel_exe ($size)"
    echo "$gomodel_exe"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local log_path="$RESULTS_DIR/gomodel-server.log"

    export PORT="$port"
    export GOMODEL_MASTER_KEY="$API_KEY"
    export OPENAI_API_KEY="$API_KEY"
    export OPENAI_BASE_URL="$MOCK_URL"
    export LOGGING_ENABLED="false"
    export USAGE_ENABLED="false"
    export ADMIN_ENDPOINTS_ENABLED="false"
    export ADMIN_UI_ENABLED="false"
    export METRICS_ENABLED="false"
    export SWAGGER_ENABLED="false"
    export GUARDRAILS_ENABLED="false"
    export PPROF_ENABLED="false"
    export CLI_TOOLS_ENABLED="false"
    export COMBOS_ENABLED="false"
    export RESPONSE_CACHE_SIMPLE_ENABLED="false"
    export SEMANTIC_CACHE_ENABLED="false"
    export TOKEN_SAVER_ENABLED="false"

    "$exe_path" > "$log_path" 2>"${log_path}.err" &
    echo $!
}
