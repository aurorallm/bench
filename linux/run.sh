#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

source "$MODULES_DIR/benchmark_utilities.sh"
source "$MODULES_DIR/benchmark_infrastructure.sh"
source "$MODULES_DIR/benchmark_comparison.sh"

COMPETITORS=""
RATE=0
DURATION=0
MODE="auto"
MOCK_PORT=9099
API_KEY="sk-bench-test-key"
MODEL="gpt-4o-mini"
WARMUP_REQUESTS=25
PREWARM_REQUESTS=256
PREWARM_CONCURRENCY=64
CONCURRENCY=256
LIST=false
CLEAN=false
SKIP_MODEL_VERIFY=false

usage() {
    echo ""
    echo "  Aurora Benchmark Framework [Linux]"
    echo "  Compare AI gateways with reproducible results."
    echo ""
    echo "USAGE"
    echo "  ./linux/run.sh [-c competitors] [-m mode] [options]"
    echo ""
    echo "HOW IT WORKS"
    echo "  1. Builds mock server + bench CLI binaries (use --clean to rebuild)"
    echo "  2. Starts Mock Server (Go HTTP server mimicking OpenAI API, port 9099)"
    echo "  3. Verifies model echo"
    echo "  4. Starts each gateway sequentially"
    echo "  5. Runs benchmark CLI at target rate x duration"
    echo "  6. Produces comparison JSON with latency percentiles, throughput, deltas"
    echo ""
    echo "BENCHMARK OPTIONS"
    echo "  -c, --competitors LIST   Comma-separated: aurora,bifrost,litellm,... (default: aurora)"
    echo "  -m, --mode MODE          smoke (100x20s), sweat (500x30s), endurance (6000x60s), publish (10000x60s), brutal (15000x60s), auto (4000x120s)"
    echo "  -r, --rate N             Target requests per second (default: auto from mode)"
    echo "  -d, --duration N         Benchmark duration in seconds (default: auto from mode)"
    echo "  -C, --concurrency N      Concurrent HTTP workers (default: 256)"
    echo "      --model NAME         Model name in request payload (default: gpt-4o-mini)"
    echo "  -p, --mock-port N        Mock server port (default: 9099)"
    echo "  -k, --api-key KEY        Auth token for all gateways"
    echo "      --warmup N           Serial warmup requests (default: 25)"
    echo "      --prewarm N          Burst prewarm requests (default: 256)"
    echo "      --prewarm-conc N     Concurrency for prewarm (default: 64)"
    echo ""
    echo "PLATFORM"
    echo "      --clean              Delete old binaries and rebuild"
    echo ""
    echo "OUTPUT"
    echo "  Results: bench-results/{gateway1-vs-gateway2}/"
    echo ""
    echo "EXAMPLES"
    echo "  ./linux/run.sh --list"
    echo "  ./linux/run.sh --clean --competitors aurora"
    echo "  ./linux/run.sh --competitors aurora,bifrost,litellm --mode smoke"
    echo ""
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--competitors)   COMPETITORS="$2"; shift 2 ;;
        -m|--mode)          MODE="$2"; shift 2 ;;
        -r|--rate)          RATE="$2"; shift 2 ;;
        -d|--duration)      DURATION="$2"; shift 2 ;;
        -C|--concurrency)   CONCURRENCY="$2"; shift 2 ;;
        --model)            MODEL="$2"; shift 2 ;;
        -p|--mock-port)     MOCK_PORT="$2"; shift 2 ;;
        -k|--api-key)       API_KEY="$2"; shift 2 ;;
        --warmup)           WARMUP_REQUESTS="$2"; shift 2 ;;
        --prewarm)          PREWARM_REQUESTS="$2"; shift 2 ;;
        --prewarm-conc)     PREWARM_CONCURRENCY="$2"; shift 2 ;;
        --list)             LIST=true; shift ;;
        --clean)            CLEAN=true; shift ;;
        --skip-model-verify) SKIP_MODEL_VERIFY=true; shift ;;
        -h|--help)          usage; exit 0 ;;
        *)                  echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

declare -A LOADED_COMPETITORS
for f in "$SCRIPT_DIR/competitors"/*.sh; do
    fname=$(basename "$f")
    [[ "$fname" == _* ]] && continue
    unset COMPETITOR_NAME COMPETITOR_DISPLAY_NAME COMPETITOR_PORT COMPETITOR_HEALTH_PATH
    unset COMPETITOR_HEALTH_TIMEOUT COMPETITOR_PREFLIGHT_SUFFIX COMPETITOR_PREFLIGHT_PATH
    unset COMPETITOR_PREFLIGHT_MODEL COMPETITOR_TYPE COMPETITOR_LANGUAGE
    unset -f competitor_install competitor_start competitor_health_check_type 2>/dev/null || true
    source "$f"
    if [ -n "${COMPETITOR_NAME:-}" ]; then
        LOADED_COMPETITORS["$COMPETITOR_NAME"]="$f"
    fi
done

if [ "$LIST" = true ]; then
    echo ""
    echo "Available competitors (Linux):"
    for name in $(printf "%s\n" "${!LOADED_COMPETITORS[@]}" | sort); do
        f="${LOADED_COMPETITORS[$name]}"
        unset COMPETITOR_DISPLAY_NAME COMPETITOR_PORT COMPETITOR_TYPE COMPETITOR_LANGUAGE
        source "$f" >/dev/null 2>&1
        printf "  %-20s" "$name"
        echo "${COMPETITOR_DISPLAY_NAME:-$name}"
        printf "    Type: %-15s" "${COMPETITOR_TYPE:-binary}"
        printf "Language: %-15s" "${COMPETITOR_LANGUAGE:-N/A}"
        echo "Port: ${COMPETITOR_PORT:-N/A}"
        echo ""
    done
    exit 0
fi

if [ -z "$COMPETITORS" ]; then
    COMPETITORS="aurora"
fi

IFS=',' read -ra SELECTED_NAMES <<< "$COMPETITORS"
SELECTED_FILES=()

for name in "${SELECTED_NAMES[@]}"; do
    name=$(echo "$name" | xargs)
    if [ -z "${LOADED_COMPETITORS[$name]:-}" ]; then
        echo "ERROR: Unknown competitor '$name'. Use --list to see available."
        exit 1
    fi
    SELECTED_FILES+=("${LOADED_COMPETITORS[$name]}")
done

echo ""
echo "======================================================================"
echo "  Aurora Benchmark Runner [Linux]"
echo "======================================================================"
echo "  Platform:  $(uname -a)"
echo "  Gateways:  ${#SELECTED_FILES[@]}"
for f in "${SELECTED_FILES[@]}"; do
    source "$f" 2>/dev/null || true
    echo "    - ${COMPETITOR_DISPLAY_NAME:-$COMPETITOR_NAME} ($COMPETITOR_NAME): port $COMPETITOR_PORT"
done

ALL_PORTS=("$MOCK_PORT")
for f in "${SELECTED_FILES[@]}"; do
    unset COMPETITOR_PORT
    source "$f" >/dev/null 2>&1 || true
    ALL_PORTS+=("${COMPETITOR_PORT}")
done

echo "  Cleaning ports: ${ALL_PORTS[*]}"
stop_processes_on_port "${ALL_PORTS[@]}" || true
sleep 1

case "$MODE" in
    auto)
        [ "$RATE" -eq 0 ] && [ "$DURATION" -eq 0 ] && { RATE=4000; DURATION=120; } ;;
    smoke)
        RATE=100; DURATION=20 ;;
    sweat)
        RATE=500; DURATION=30 ;;
    endurance)
        RATE=6000; DURATION=60 ;;
    publish)
        RATE=10000; DURATION=60 ;;
    brutal)
        RATE=15000; DURATION=60 ;;
esac
[ "$RATE" -le 0 ] && RATE=1000
[ "$DURATION" -le 0 ] && DURATION=30

echo "  Rate:      $RATE req/s"
echo "  Duration:  ${DURATION}s"
echo "  Mock port: $MOCK_PORT"
echo "  Model:     $MODEL"
echo "  Clean build: $CLEAN"
echo "  Verify model: $([ "$SKIP_MODEL_VERIFY" = false ] && echo 'yes' || echo 'no')"
echo "======================================================================"
echo ""

if [ "$CLEAN" = true ]; then
    echo "Cleaning old binaries and rebuilding fresh..."
    clear_bench_binaries "$BENCH_DIR"
    build_all_binaries "$BENCH_DIR"
    MOCK_EXE="$BENCH_DIR/bin/linux/mock-server"
    CLI_PATH="$BENCH_DIR/bin/linux/aurora-bench-cli"
else
    MOCK_EXE=$(build_mock_server "$BENCH_DIR")
    CLI_PATH=$(build_bench_cli "$BENCH_DIR")
fi

PLATFORM="linux"
RESULTS_DIR="$BENCH_DIR/bench-results"
SCENARIO_LABEL=$(IFS=-; echo "${SELECTED_NAMES[*]}")
SCENARIO_LABEL="${SCENARIO_LABEL// /}"
RUN_DIR="$RESULTS_DIR/$PLATFORM/${SCENARIO_LABEL//,/-vs-}"
mkdir -p "$RUN_DIR"

echo "Starting mock server on port $MOCK_PORT..."
MOCK_PID=$(start_mock_server_process "$MOCK_EXE" "$MOCK_PORT" "$MODEL")
wait_for_health "Mock Server" "$MOCK_PORT" 15

if [ "$SKIP_MODEL_VERIFY" = false ]; then
    echo ""
    echo "Verifying mock server model..."
    verify_mock_server_model "$MOCK_PORT" "$MODEL"
    echo ""
fi

MOCK_URL="http://127.0.0.1:$MOCK_PORT"

trap 'echo "  Cleaning up..."; stop_bench_processes; sleep 1' EXIT

source "$SCRIPT_DIR/modules/benchmark_utilities.sh"
source "$SCRIPT_DIR/modules/benchmark_infrastructure.sh"

bash "$SCRIPT_DIR/scenarios/compare.sh" \
    --competitor-files "$(IFS=','; echo "${SELECTED_FILES[*]}")" \
    --bench-dir "$BENCH_DIR" \
    --results-dir "$RUN_DIR" \
    --mock-url "$MOCK_URL" \
    --api-key "$API_KEY" \
    --rate "$RATE" \
    --duration "$DURATION" \
    --warmup "$WARMUP_REQUESTS" \
    --prewarm "$PREWARM_REQUESTS" \
    --prewarm-conc "$PREWARM_CONCURRENCY" \
    --model "$MODEL" \
    --endpoint-suffix "v1" \
    --endpoint-path "chat/completions" \
    --cli-path "$CLI_PATH" \
    --concurrency "$CONCURRENCY"
