# Aurora Benchmark: Platform Comparison & Gap Analysis

**Date:** 2026-07-22
**Purpose:** What's already done on each platform, what's missing, and exact variables to use.

---

## 1. Code Defaults Now Match Bench-Optimized Values

The following settings were promoted from bench scripts to source code defaults so every Aurora Gateway deployment benefits without env var changes:

| Setting | Old Code Default | New Code Default | File |
|---|---|---|---|
| `HTTP_MAX_CONNS_PER_HOST` | `0` (unlimited) | `256` | `internal/http_client/client.go:168` |
| `PROMPT_CACHE_MODE` | `"auto"` | `"off"` | `configuration/cache.go:23` |

### Already-optimal code defaults (unchanged, bench-confirmed):

| Setting | Code Default |
|---|---|
| `HTTP_MAX_IDLE_CONNS` | `4096` |
| `HTTP_MAX_IDLE_CONNS_PER_HOST` | `4096` |
| h2c (HTTP/2 cleartext) | always-on via `configureGatewayHTTPServer()` |
| `DISABLE_REQUEST_LOGGING` | `true` |
| `GUARDRAILS_ENABLED` | `false` |
| `USAGE_ENABLED` | `false` |
| `LOGGING_ENABLED` | `false` |
| `METRICS_ENABLED` | `false` |
| `SEMANTIC_CACHE_ENABLED` | `false` (disabled) |
| `RESPONSE_CACHE_SIMPLE_ENABLED` | `false` (disabled) |
| `TOKEN_SAVER_ENABLED` | `false` |
| `SWAGGER_ENABLED` | `false` |
| `ENABLE_ANTHROPIC_INGRESS` | `false` |
| `CLI_TOOLS_ENABLED` | `false` |
| `COMBOS_ENABLED` | `false` |
| `ADMIN_ENDPOINTS_ENABLED` | `false` |
| `ADMIN_UI_ENABLED` | `false` |
| `MODEL_LIST_URL` | `""` |

**Result:** `aurora-default` variant (no env overrides) now performs virtually identically to the previous `aurora` variant.

---

## 2. Competitor Profiles — What Each Variant Sets

### `aurora` (Primary — Full Bench Mode)

**Linux** (`linux/competitors/aurora.sh`) and **Windows** (`windows/competitors/aurora.ps1`) are **identical**:

| Variable | Value | Why | Status |
|---|---|---|---|
| `AURORA_MINIMAL_BENCH_MODE` | `true` | Forces request logging off, skips telemetry + auth rate limiter | **REQUIRED** |
| `AURORA_CHAT_FAST_PATH_PASSTHROUGH` | `true` | +15-20% throughput — bypasses JSON decode/re-encode | **REQUIRED** |
| `HTTP_MAX_CONNS_PER_HOST` | `256` | Prevents upstream connection exhaustion | **REQUIRED** |
| `DISABLE_REQUEST_BODY_SNAPSHOT` | `true` | Skips eager body capture (~3% CPU) | **REQUIRED** |
| `DISABLE_PASSTHROUGH_SEMANTIC_ENRICHMENT` | `true` | Skips passthrough metadata enrichment | **REQUIRED** |
| `PPROF_ENABLED` | `true` | Diagnostics during benchmark | Diagnostic |
| `GOMEMLIMIT` | `6000MiB` | Go runtime soft memory limit | Tuning |
| `CIRCUIT_BREAKER_FAILURE_THRESHOLD` | `0` | Disables circuit breaker for bench | Tuning |

All other feature-disablement vars were removed — they match code defaults.

### `aurora-default` (Baseline — No Tuning)

Pure out-of-the-box defaults. Only `PORT`, `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `AURORA_MASTER_KEY` are set.

### `aurora-tuned` (Bench-mode Tuning Only)

Same as default but adds `AURORA_MINIMAL_BENCH_MODE=true` and `AURORA_CHAT_FAST_PATH_PASSTHROUGH=true`.

---

## 3. Platform Differences

| Aspect | Linux | Windows |
|---|---|---|
| `PPROF_ENABLED` | `true` in `aurora` | `true` in `aurora` (fixed) |
| Profiling | curl pprof during benchmark (compare.sh) | **No pprof collection** in compare.ps1 |
| Process management | `kill $PID` | `Stop-Process` |
| Binary path | `bin/linux/aurora-bench` | `bin\windows\aurora-bench.exe` |
| H2C support | Works natively | Works via `SO_CONDITIONAL_ACCEPT` always-on |
| Socket tuning | Standard `net.Listen` | `SO_CONDITIONAL_ACCEPT` always-on |
| Mock server | Same Go binary | Same Go binary |
| Docker variant | `aurora-docker.sh` exists | None |

### What Linux Has That Windows Doesn't

1. **pprof profiling during benchmark** — `compare.sh` lines 104-128 collect CPU/heap/goroutine/block/mutex profiles. `compare.ps1` does NOT collect any profiles.

2. **aurora-docker variant** — Docker-based competitor only on Linux.

### What Windows Has That Linux Doesn't

1. **`BenchmarkProfiling.psm1`** module — imported but not used in compare.ps1 flow.

2. **`aurora-standalone.ps1`** scenario — standalone benchmark with bifrost-benchmarking tool integration.

---

## 4. Remaining Issues

### Known Gaps

| Issue | Evidence | Status |
|---|---|---|
| **No pprof on Windows** | Cannot diagnose CPU hotspots on Windows runs | Unfixed |
| **Double JSON parse** | CPU profile shows 15% in JSON. `ChatRequest.UnmarshalJSON` does goccy/go-json Unmarshal + gjson ForEach. Body snapshot already did gjson peek. | Code issue |
| **GC pressure** | 68 allocs/op, 5.8KB/op. CPU profile shows 25% in GC. | Code issue |

### Dead Variables (Removed from Bench Scripts)

| Variable | Reason |
|---|---|
| `IDENTITY_ENABLED=false` | Enterprise-only — no OSS code reads it |
| `AURORA_H2C_ENABLED=true` | h2c is unconditionally on — zero effect |
| `HTTP_MAX_IDLE_CONNS=4096` | Code default is 4096 |
| `HTTP_MAX_IDLE_CONNS_PER_HOST=4096` | Code default is 4096 |
| `MODEL_LIST_URL=""` | Code default is `""` |
| `STORAGE_TYPE=sqlite` | Code default is `"sqlite"` |
| All `*_ENABLED=false` vars | Code defaults are all `false` |
