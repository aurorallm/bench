COMPETITOR_NAME="helicone-native"
COMPETITOR_DISPLAY_NAME="Helicone AI Gateway (Native)"
COMPETITOR_LANGUAGE="Rust"
COMPETITOR_PORT=8585
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_health_check_type() { echo "tcp"; }

competitor_install() {
    local exe_dir="$BENCH_DIR/bin/darwin"
    local exe_path="$exe_dir/helicone-gateway"

    if [ -f "$exe_path" ]; then
        local size
        size=$(du -h "$exe_path" 2>/dev/null | cut -f1)
        echo "  Helicone native binary: $exe_path ($size)"
        echo "$exe_path"
        return 0
    fi

    echo "  Helicone binary not found. Downloading from GitHub releases..."
    mkdir -p "$exe_dir"

    local arch
    arch=$(uname -m)
    [ "$arch" = "x86_64" ] && arch="amd64"
    [ "$arch" = "aarch64" ] && arch="arm64"

    echo "  Looking up latest Helicone release..."
    local releases
    releases=$(curl -sf "https://api.github.com/repos/Helicone/ai-gateway/releases?per_page=1" 2>/dev/null) || {
        echo "  ERROR: Failed to fetch release info"
        return 1
    }

    local tag
    tag=$(echo "$releases" | jq -r '.[0].tag_name')
    echo "  Latest release: $tag"

    local asset_filter="darwin_${arch}\\.tar\\.xz$"
    local asset_name
    asset_name=$(echo "$releases" | jq -r --arg arch "$arch" '.[0].assets[] | select(.name | test("darwin_"+$arch+"\\.tar\\.xz$") and (.name | test("sha256") | not)) | .name' | head -1)
    if [ -z "$asset_name" ]; then
        asset_name=$(echo "$releases" | jq -r '.[0].assets[] | select(.name | test("darwin_amd64\\.tar\\.xz$") and (.name | test("sha256") | not)) | .name' | head -1)
    fi

    [ -z "$asset_name" ] && echo "  ERROR: No darwin tar.xz asset found" && return 1

    local download_url="https://github.com/Helicone/ai-gateway/releases/download/$tag/$asset_name"
    local tar_path="$exe_dir/helicone.tar.xz"

    echo "  Downloading: $asset_name"
    curl -fL "$download_url" -o "$tar_path" || return 1

    echo "  Extracting..."
    tar -xJf "$tar_path" -C "$exe_dir" 2>/dev/null
    rm -f "$tar_path"

    local extracted
    extracted=$(find "$exe_dir" -maxdepth 1 -type f -name "ai-gateway" 2>/dev/null | head -1)
    [ -z "$extracted" ] && echo "  ERROR: No ai-gateway binary found in archive" && return 1

    mv "$extracted" "$exe_path"
    chmod +x "$exe_path"

    local size
    size=$(du -h "$exe_path" 2>/dev/null | cut -f1)
    echo "  Helicone extracted: $exe_path ($size)"
    echo "$exe_path"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local config_path="$RESULTS_DIR/helicone-config.yaml"

    cat > "$config_path" << CFGEOF
providers:
  openai:
    models:
      - "gpt-4o-mini"
    base-url: "${MOCK_URL}/v1"
CFGEOF

    export OPENAI_API_KEY="$API_KEY"
    export RUST_LOG="error"

    "$exe_path" --config "$config_path" > /dev/null 2>&1 &
    echo $!
}
