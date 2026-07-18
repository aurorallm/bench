COMPETITOR_NAME="apisix"
COMPETITOR_DISPLAY_NAME="Apache APISIX"
COMPETITOR_LANGUAGE="Lua/Nginx"
COMPETITOR_PORT=9080
COMPETITOR_HEALTH_TIMEOUT=60
COMPETITOR_PREFLIGHT_SUFFIX="v1"
COMPETITOR_PREFLIGHT_PATH="chat/completions"
COMPETITOR_PREFLIGHT_MODEL="gpt-4o-mini"
COMPETITOR_TYPE="docker"

competitor_health_check_type() { echo "tcp"; }

competitor_install() {
    if ! command -v docker &>/dev/null; then
        echo "  ERROR: Docker not found."
        return 1
    fi
    echo "  APISIX via Docker (apache/apisix)..."
    echo "docker"
}

competitor_start() {
    local exe_path="$1"
    local port="$2"
    local mock_port
    mock_port=$(echo "$MOCK_URL" | sed 's/.*://')

    docker rm -f apisix-bench 2>/dev/null

    local config_yaml_path="$RESULTS_DIR/apisix-config.yaml"
    cat > "$config_yaml_path" << 'YAMLEOF'
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
apisix:
  enable_admin: false
plugins: []
nginx_config:
  main_config: |
    access_log /dev/null;
    error_log /dev/null crit;
  http_config: |
    access_log /dev/null;
    error_log /dev/null crit;
YAMLEOF

    local template_path="$BENCH_DIR/configs/apisix-bench.yaml"
    local apisix_content
    apisix_content=$(sed "s/MOCK_PORT/$mock_port/g" "$template_path")
    local apisix_yaml_path="$RESULTS_DIR/apisix.yaml"
    echo "$apisix_content" > "$apisix_yaml_path"

    docker run -d --rm --name apisix-bench \
        --log-driver none \
        -p "${port}:9080" \
        -e APISIX_STAND_ALONE=true \
        -v "${config_yaml_path}:/usr/local/apisix/conf/config.yaml" \
        -v "${apisix_yaml_path}:/usr/local/apisix/conf/apisix.yaml" \
        apache/apisix > /dev/null 2>&1

    local container_id
    container_id=$(docker ps -q -f name=apisix-bench)
    if [ -n "$container_id" ]; then
        docker inspect "$container_id" | jq -r '.[0].State.Pid'
    else
        echo ""
    fi
}
