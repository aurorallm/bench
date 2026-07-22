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
    local aurora_exe="$BENCH_DIR/bin/linux/aurora-bench"
    if [ -f "$aurora_exe" ]; then
        echo "$aurora_exe"
        return 0
    fi

    echo "  Aurora binary not found. Downloading from GitHub releases..." >&2
    local bin_dir="$BENCH_DIR/bin/linux"
    mkdir -p "$bin_dir"

    echo "  Looking up latest Aurora release..." >&2
    local release
    release=$(curl -sf "https://api.github.com/repos/aurorallm/aurora/releases/latest" 2>/dev/null) || {
        echo "  ERROR: Failed to fetch release info" >&2
        return 1
    }

    local tag
    tag=$(echo "$release" | jq -r '.tag_name')
    echo "  Latest release: $tag" >&2

    local asset_name
    asset_name=$(echo "$release" | jq -r '.assets[] | select(.name | test("linux_amd64\\.tar\\.gz$")) | .name' | head -1)
    [ -z "$asset_name" ] && echo "  ERROR: No Linux amd64 tar.gz asset found" && return 1

    local download_url="https://github.com/aurorallm/aurora/releases/download/$tag/$asset_name"
    local tar_path="$bin_dir/aurora.tar.gz"

    echo "  Downloading: $asset_name" >&2
    curl -fL "$download_url" -o "$tar_path" || return 1

    echo "  Extracting..." >&2
    tar -xzf "$tar_path" -C "$bin_dir" 2>/dev/null
    rm -f "$tar_path"

    local extracted
    extracted=$(find "$bin_dir" -maxdepth 1 -type f -name "aurora" 2>/dev/null | head -1)
    [ -z "$extracted" ] && echo "  ERROR: No aurora binary found in archive" && return 1

    [ "$extracted" != "$aurora_exe" ] && mv "$extracted" "$aurora_exe"
    chmod +x "$aurora_exe"

    local size
    size=$(du -h "$aurora_exe" 2>/dev/null | cut -f1)
    echo "  Aurora extracted: $aurora_exe ($size)" >&2
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

    # Performance tuning overrides (differs from code defaults)
    export AURORA_MINIMAL_BENCH_MODE="true"
    export AURORA_CHAT_FAST_PATH_PASSTHROUGH="true"
    export HTTP_MAX_CONNS_PER_HOST="256"
    export PPROF_ENABLED="true"
    export GOMEMLIMIT="6000MiB"
    export CIRCUIT_BREAKER_FAILURE_THRESHOLD="0"
    export DISABLE_REQUEST_BODY_SNAPSHOT="true"
    export DISABLE_PASSTHROUGH_SEMANTIC_ENRICHMENT="true"

    # Code defaults that are already optimal (no override needed):
    #   HTTP_MAX_IDLE_CONNS=4096, HTTP_MAX_IDLE_CONNS_PER_HOST=4096,
    #   MODEL_LIST_URL="", STORAGE_TYPE=sqlite, PROMPT_CACHE_MODE=off,
    #   GUARDRAILS_ENABLED=false, USAGE_ENABLED=false, LOGGING_ENABLED=false,
    #   METRICS_ENABLED=false, SEMANTIC_CACHE_ENABLED=false,
    #   RESPONSE_CACHE_SIMPLE_ENABLED=false, TOKEN_SAVER_ENABLED=false,
    #   SWAGGER_ENABLED=false, ENABLE_ANTHROPIC_INGRESS=false,
    #   CLI_TOOLS_ENABLED=false, COMBOS_ENABLED=false,
    #   ADMIN_ENDPOINTS_ENABLED=false, ADMIN_UI_ENABLED=false,
    #   DISABLE_REQUEST_LOGGING=true, AURORA_H2C_ENABLED always-on

    local old_pwd="$PWD"
    cd "$bench_work_dir" && "$exe_path" > "$log_path" 2>"${log_path}.err" &
    cd "$old_pwd" 2>/dev/null || true
    echo $!
}
