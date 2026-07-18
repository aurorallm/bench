COMPETITOR_NAME="helicone-native"
COMPETITOR_DISPLAY_NAME="Helicone AI Gateway (Native)"
COMPETITOR_LANGUAGE="Rust"
COMPETITOR_PORT=8080
COMPETITOR_HEALTH_TIMEOUT=30
COMPETITOR_PREFLIGHT_SUFFIX="openai"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_BENCHMARK_PATH="openai/chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="binary"

# Helicone native uses TCP health check
competitor_health_check_type() { echo "tcp"; }

competitor_install() {
    local exe_dir="$BENCH_DIR/bin/linux"
    local exe_path="$exe_dir/helicone-gateway"

    if [ -f "$exe_path" ]; then
        local size
        size=$(du -h "$exe_path" 2>/dev/null | cut -f1)
        echo "  Helicone native binary: $exe_path ($size)" >&2
        echo "$exe_path"
        return 0
    fi

    echo "  Helicone binary not found. Downloading from GitHub releases..." >&2
    mkdir -p "$exe_dir"

    local tag asset_name tar_path="$exe_dir/helicone.tar.xz"

    if command -v gh &>/dev/null; then
        echo "  Looking up latest Helicone release via gh..." >&2
        tag=$(gh release list -R Helicone/ai-gateway --json tagName -q '.[0].tagName' 2>/dev/null) || {
            echo "  ERROR: Failed to fetch release info via gh" >&2
            return 1
        }
        echo "  Latest release: $tag" >&2
        asset_name=$(gh release view "$tag" -R Helicone/ai-gateway --json assets -q '.assets[] | select(.name | contains("linux-gnu") and (contains("sha256") | not)) | .name' 2>/dev/null | head -1)
        [ -z "$asset_name" ] && echo "  ERROR: No Linux amd64 tar.xz asset found" && return 1

        echo "  Downloading: $asset_name" >&2
        gh release download "$tag" -R Helicone/ai-gateway -p "$asset_name" -O "$tar_path" || return 1
    else
        echo "  Looking up latest Helicone release via curl..." >&2
        local releases
        releases=$(curl -sf "https://api.github.com/repos/Helicone/ai-gateway/releases?per_page=1" 2>/dev/null) || {
            echo "  ERROR: Failed to fetch release info" >&2
            return 1
        }

        tag=$(echo "$releases" | jq -r '.[0].tag_name')
        echo "  Latest release: $tag" >&2

        asset_name=$(echo "$releases" | jq -r '.[0].assets[] | select(.name | contains("linux-gnu") and (contains("sha256") | not)) | .name' | head -1)
        [ -z "$asset_name" ] && echo "  ERROR: No Linux amd64 tar.xz asset found" && return 1

        local download_url="https://github.com/Helicone/ai-gateway/releases/download/$tag/$asset_name"
        echo "  Downloading: $asset_name" >&2
        curl -fL "$download_url" -o "$tar_path" || return 1
    fi

    echo "  Extracting..." >&2
    local tmp_extract="$exe_dir/helicone-extract"
    mkdir -p "$tmp_extract"
    tar -xJf "$tar_path" -C "$tmp_extract" 2>/dev/null
    rm -f "$tar_path"

    local extracted
    extracted=$(find "$tmp_extract" -type f -name "ai-gateway" 2>/dev/null | head -1)
    [ -z "$extracted" ] && echo "  ERROR: No ai-gateway binary found in archive" && return 1

    mv "$extracted" "$exe_path"
    rm -rf "$tmp_extract"
    chmod +x "$exe_path"

    local size
    size=$(du -h "$exe_path" 2>/dev/null | cut -f1)
    echo "  Helicone extracted: $exe_path ($size)" >&2
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
