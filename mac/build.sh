#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$BENCH_DIR/bin/darwin"

echo ""
echo "======================================================================"
echo "  Aurora Benchmark Build [macOS]"
echo "======================================================================"
echo "  Repo root: $BENCH_DIR"
echo "  Bin dir:   $BIN_DIR"
echo "======================================================================"
echo ""

mkdir -p "$BIN_DIR"

CLEAN="${1:-}"
if [ "$CLEAN" = "--clean" ] || [ "$CLEAN" = "-clean" ]; then
    echo "Cleaning old binaries..."
    find "$BIN_DIR" -type f ! -name '.*' -delete
    echo "  Cleaned $BIN_DIR"
    echo ""
fi

ARCH="${GOARCH:-}"
if [ -z "$ARCH" ]; then
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        arm64)        ARCH="arm64" ;;
        *)            echo "ERROR: Unsupported arch: $(uname -m)"; exit 1 ;;
    esac
fi

echo "  Building for darwin/$ARCH"
echo ""

MOCK_OUT="$BIN_DIR/mock-server"
echo "[1/3] Building mock server..."
(cd "$BENCH_DIR/mock-server" && GOOS=darwin GOARCH="$ARCH" go build -o "$MOCK_OUT" ./main.go)
if [ ! -f "$MOCK_OUT" ]; then echo "ERROR: mock server build failed"; exit 1; fi
echo "  -> $MOCK_OUT"

CLI_OUT="$BIN_DIR/aurora-bench-cli"
CLI_SRC="$BENCH_DIR/tools/benchmark-cli"
echo "[2/3] Building benchmark CLI..."
(cd "$BENCH_DIR" && GOOS=darwin GOARCH="$ARCH" go build -o "$CLI_OUT" "$CLI_SRC")
if [ ! -f "$CLI_OUT" ]; then echo "ERROR: benchmark CLI build failed"; exit 1; fi
echo "  -> $CLI_OUT"

AURORA_OUT="$BIN_DIR/aurora-bench"
echo "[3/3] Aurora gateway..."
if [ -f "$AURORA_OUT" ]; then
    echo "  Using pre-built Aurora: $AURORA_OUT"
else
    echo "  WARNING: No pre-built Aurora binary at $AURORA_OUT"
    echo "  Aurora benchmarks will not work until a binary is placed there."
fi

echo ""
echo "======================================================================"
echo "  Build complete!"
echo "======================================================================"
if [ -f "$MOCK_OUT" ]; then echo "  mock-server:       $(du -h "$MOCK_OUT" | cut -f1)"; fi
if [ -f "$CLI_OUT" ]; then echo "  aurora-bench-cli:  $(du -h "$CLI_OUT" | cut -f1)"; fi
if [ -f "$AURORA_OUT" ]; then echo "  aurora-bench:      $(du -h "$AURORA_OUT" | cut -f1)"; fi
echo "======================================================================"
echo ""

if [ "${2:-}" = "--run" ] || [ "${2:-}" = "-run" ]; then
    echo "Starting benchmark via mac/run.sh..."
    bash "$SCRIPT_DIR/run.sh"
fi
