#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --competitor-files) COMPETITOR_FILES="$2"; shift 2 ;;
        --bench-dir)        BENCH_DIR="$2"; shift 2 ;;
        --results-dir)      RESULTS_DIR="$2"; shift 2 ;;
        --mock-url)         MOCK_URL="$2"; shift 2 ;;
        --api-key)          API_KEY="$2"; shift 2 ;;
        --rate)             RATE="$2"; shift 2 ;;
        --duration)         DURATION="$2"; shift 2 ;;
        --warmup)           WARMUP_REQUESTS="$2"; shift 2 ;;
        --prewarm)          PREWARM_REQUESTS="$2"; shift 2 ;;
        --prewarm-conc)     PREWARM_CONCURRENCY="$2"; shift 2 ;;
        --model)            MODEL="$2"; shift 2 ;;
        --endpoint-suffix)  ENDPOINT_SUFFIX="$2"; shift 2 ;;
        --endpoint-path)    ENDPOINT_PATH="$2"; shift 2 ;;
        --cli-path)         CLI_PATH="$2"; shift 2 ;;
        --concurrency)      CONCURRENCY="$2"; shift 2 ;;
        *)                  echo "Unknown compare.sh option: $1"; exit 1 ;;
    esac
done

source "$PLATFORM_DIR/modules/benchmark_utilities.sh"
source "$PLATFORM_DIR/modules/benchmark_infrastructure.sh"
source "$PLATFORM_DIR/modules/benchmark_comparison.sh"

declare -A RESULTS

IFS=',' read -ra FILES <<< "$COMPETITOR_FILES"
for f in "${FILES[@]}"; do
    f=$(echo "$f" | xargs)
    [ -z "$f" ] && continue

    unset COMPETITOR_NAME COMPETITOR_DISPLAY_NAME COMPETITOR_PORT COMPETITOR_HEALTH_PATH
    unset COMPETITOR_HEALTH_TIMEOUT COMPETITOR_PREFLIGHT_SUFFIX COMPETITOR_PREFLIGHT_PATH
    unset COMPETITOR_PREFLIGHT_MODEL COMPETITOR_TYPE COMPETITOR_LANGUAGE COMPETITOR_BENCHMARK_PATH
    unset -f competitor_install competitor_start competitor_health_check_type 2>/dev/null || true
    source "$f"

    NAME="${COMPETITOR_NAME}"
    DISPLAY="${COMPETITOR_DISPLAY_NAME:-$NAME}"
    PORT="${COMPETITOR_PORT}"
    HEALTH_PATH="${COMPETITOR_HEALTH_PATH:-health}"
    HEALTH_TIMEOUT="${COMPETITOR_HEALTH_TIMEOUT:-30}"
    PREFLIGHT_SUFFIX="${COMPETITOR_PREFLIGHT_SUFFIX:-$ENDPOINT_SUFFIX}"
    PREFLIGHT_PATH="${COMPETITOR_PREFLIGHT_PATH:-$ENDPOINT_PATH}"
    PREFLIGHT_MODEL="${COMPETITOR_PREFLIGHT_MODEL:-$MODEL}"
    BENCH_PATH="${COMPETITOR_BENCHMARK_PATH:-$PREFLIGHT_SUFFIX/$PREFLIGHT_PATH}"

    echo ""
    echo "======================================================================"
    echo "  Gateway: $DISPLAY ($NAME) on port $PORT"
    echo "======================================================================"

    stop_processes_on_port "$PORT"
    sleep 1

    EXE_PATH=$(competitor_install); local INSTALL_EXIT=$?
    if [ -z "$EXE_PATH" ] || [ $INSTALL_EXIT -ne 0 ]; then
        echo "  ERROR: competitor_install failed for $NAME. Skipping."
        continue
    fi

    echo "  Starting $DISPLAY..."
    PROC_PID=$(competitor_start "$EXE_PATH" "$PORT")
    if [ -z "$PROC_PID" ]; then
        echo "  ERROR: competitor_start failed for $NAME. Skipping."
        continue
    fi

    echo "  Waiting for $DISPLAY health check (${HEALTH_TIMEOUT}s)..."
    HEALTH_CHECK_TYPE="http"
    if declare -F competitor_health_check_type >/dev/null 2>&1; then
        HEALTH_CHECK_TYPE=$(competitor_health_check_type)
    fi
    wait_for_health "$DISPLAY" "$PORT" "$HEALTH_TIMEOUT" "$HEALTH_PATH" "$HEALTH_CHECK_TYPE"

    echo "  Running preflight..."
    invoke_preflight "$NAME" "$PORT" "$PREFLIGHT_MODEL" "$PREFLIGHT_SUFFIX" "$PREFLIGHT_PATH" "$API_KEY"

    if [ "$PREWARM_REQUESTS" -gt 0 ] 2>/dev/null; then
        PREWARM_OUT="$RESULTS_DIR/${NAME}.prewarm.json"
        echo "  Prewarming (${PREWARM_REQUESTS}r @ ${PREWARM_CONCURRENCY}c)..."
        invoke_benchmark "$DISPLAY" "$PORT" "$PREWARM_OUT" \
            "$RATE" "10" "$PREWARM_CONCURRENCY" "$PREFLIGHT_MODEL" "$BENCH_PATH" \
            "$API_KEY" "$WARMUP_REQUESTS" "$CLI_PATH" "$MOCK_URL" "Prewarm"
    fi

    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUT_PATH="$RESULTS_DIR/${TIMESTAMP}.${NAME}.json"
    echo "  Running benchmark ($RATE req/s, ${DURATION}s)..."
    invoke_benchmark "$DISPLAY" "$PORT" "$OUT_PATH" \
        "$RATE" "$DURATION" "$CONCURRENCY" "$PREFLIGHT_MODEL" "$BENCH_PATH" \
        "$API_KEY" "0" "$CLI_PATH" "$MOCK_URL" "Benchmark"

    RESULTS["$NAME"]="$OUT_PATH"

    echo "  Stopping $DISPLAY..."
    if [ -n "$PROC_PID" ] && [ "$PROC_PID" -gt 1 ] 2>/dev/null; then
        kill "$PROC_PID" 2>/dev/null || true
    fi
    stop_processes_on_port "$PORT"

    LAST_INDEX=$((${#FILES[@]} - 1))
    if [ "$f" != "${FILES[$LAST_INDEX]}" ]; then
        echo "  Cooldown 5s..."
        sleep 5
    fi
done

echo ""
echo "======================================================================"
echo "  Generating comparison..."
echo "======================================================================"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
COMPARISON_OUT="$RESULTS_DIR/${TIMESTAMP}.comparison.json"

RESULTS_JSON="{"
FIRST=true
for name in "${!RESULTS[@]}"; do
    path="${RESULTS[$name]}"
    if [ -f "$path" ]; then
        [ "$FIRST" = true ] && FIRST=false || RESULTS_JSON+=", "
        RESULTS_JSON+="\"$name\": $(cat "$path")"
    fi
done
RESULTS_JSON+="}"

write_generic_comparison "$RESULTS_JSON" "$COMPARISON_OUT" "$RATE" "$DURATION" "$MODEL" "/$ENDPOINT_SUFFIX/$ENDPOINT_PATH"
write_comparison_summary "$COMPARISON_OUT"

echo ""
echo "All benchmarks complete."
echo "Results: $RESULTS_DIR"
