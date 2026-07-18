COMPETITOR_NAME="litellm"
COMPETITOR_DISPLAY_NAME="LiteLLM Gateway"
COMPETITOR_LANGUAGE="Python"
COMPETITOR_PORT=8082
COMPETITOR_HEALTH_PATH="health/liveliness"
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="pip"

competitor_install() {
    if ! command -v litellm &>/dev/null; then
        echo "  LiteLLM not found. Installing..." >&2
        pip install litellm[proxy] 2>/dev/null || {
            echo "  ERROR: LiteLLM installation failed" >&2
            return 1
        }
    fi
    local litellm_path
    litellm_path=$(command -v litellm)
    echo "  LiteLLM found: $litellm_path" >&2
    echo "$litellm_path"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local cfg_out="$RESULTS_DIR/litellm-config.yaml"

    cat > "$cfg_out" << CFGEOF
model_list:
  - model_name: "gpt-4o-mini"
    litellm_params:
      model: "openai/gpt-4o-mini"
      api_key: "$API_KEY"
      api_base: "$MOCK_URL/v1"

general_settings:
  master_key: null
  disable_spend_logs: true
  disable_error_logs: true
  disable_spend_updates: true
  disable_reset_budget: true
  disable_master_key_return: true
  disable_adding_master_key_hash_to_db: true

litellm_settings:
  num_retries: 0
  request_timeout: 60
  drop_params: true
  cache: false
  success_callback: []
  failure_callback: []
  callbacks: []

router_settings:
  disable_cooldowns: true
  routing_strategy: simple-shuffle
CFGEOF

    export NO_DOCS="True"
    export NO_REDOC="True"
    export LITELLM_TELEMETRY="False"
    export DISABLE_ADMIN_UI="True"
    export LITELLM_LOG="CRITICAL"

    "$exe_path" --config "$cfg_out" --port "$port" --telemetry False > /dev/null 2>&1 &
    echo $!
}
