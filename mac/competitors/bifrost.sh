COMPETITOR_NAME="bifrost"
COMPETITOR_DISPLAY_NAME="Bifrost Gateway"
COMPETITOR_LANGUAGE="Go"
COMPETITOR_PORT=8080
COMPETITOR_HEALTH_PATH="health"
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="openai/gpt-4o-mini"
COMPETITOR_TYPE="binary"

competitor_install() {
    local exe_path
    exe_path=$(find_bifrost_binary)
    if [ -z "$exe_path" ]; then
        echo "  Bifrost binary not found. Install with:"
        echo "    npx -y @maximhq/bifrost --help"
        echo "  Or set BIFROST_EXE_PATH"
        return 1
    fi
    echo "Bifrost found: $exe_path"
    echo "$exe_path"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local app_dir="$RESULTS_DIR/bifrost-app"
    mkdir -p "$app_dir"

    local config_dir="$BENCH_DIR/configs"
    local config_path="$config_dir/bifrost-config.json"
    if [ -f "$config_path" ]; then
        local tmp_config="$app_dir/config.json"
        jq --arg url "$MOCK_URL" --arg key "$API_KEY" '
            .providers.openai.network_config.base_url = $url |
            .providers.openai.keys[0].value = $key |
            .config_store.enabled = false |
            .client.enable_logging = false |
            .client.disable_content_logging = true |
            .logs_store.enabled = false |
            .logs_store.type = "sqlite"
        ' "$config_path" > "$tmp_config"
    fi

    "$exe_path" -port "$port" -host "127.0.0.1" -app-dir "$app_dir" -log-level error > /dev/null 2>&1 &
    echo $!
}

find_bifrost_binary() {
    if [ -n "$BIFROST_EXE_PATH" ] && [ -f "$BIFROST_EXE_PATH" ]; then
        echo "$BIFROST_EXE_PATH"
        return
    fi

    local npx_bin
    npx_bin=$(command -v npx 2>/dev/null || which npx 2>/dev/null || echo "")
    if [ -n "$npx_bin" ]; then
        local bifrost_path
        bifrost_path=$(npx -y @maximhq/bifrost --help 2>/dev/null 1>/dev/null; which bifrost-http 2>/dev/null)
        if [ -n "$bifrost_path" ] && [ -f "$bifrost_path" ]; then
            echo "$bifrost_path"
            return
        fi
    fi
}
