# Portkey AI Gateway
# HealthCheckType = "tcp", HealthPath = "v1/models"

COMPETITOR_NAME="portkey"
COMPETITOR_DISPLAY_NAME="Portkey AI Gateway"
COMPETITOR_LANGUAGE="TypeScript"
COMPETITOR_PORT=8787
COMPETITOR_HEALTH_PATH="v1/models"
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="npm"

competitor_health_check_type() { echo "tcp"; }

competitor_install() {
    if command -v npx &>/dev/null; then
        echo "  Portkey via npx..."
        echo "npx"
        return 0
    fi
    echo "  ERROR: npx not found. Install Node.js first."
    return 1
}

competitor_start() {
    local exe_path="$1"
    local port="$2"

    export OPENAI_API_KEY="$API_KEY"
    export NODE_ENV="production"

    npx -y @portkey-ai/gateway > /dev/null 2>&1 &
    echo $!
}
