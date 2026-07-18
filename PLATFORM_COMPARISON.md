# Aurora Benchmark: Platform Comparison & Gap Analysis

**Date:** 2026-07-17
**Purpose:** What's already done on each platform, what's missing, and exact variables to use.

---

## 1. Competitor Profiles — What Each Variant Sets

### `aurora` (Primary — Full Bench Mode)

**Linux** (`linux/competitors/aurora.sh`) and **Windows** (`windows/competitors/aurora.ps1`) are **identical** in feature set:

| Variable | Value | Status |
|----------|-------|--------|
| `AURORA_MINIMAL_BENCH_MODE` | `true` | **SET** — disables request logging, body snapshot, usage |
| `AURORA_H2C_ENABLED` | `true` | **SET** — HTTP/2 multiplexing |
| `HTTP_MAX_IDLE_CONNS` | `4096` | **SET** |
| `HTTP_MAX_IDLE_CONNS_PER_HOST` | `4096` | **SET** |
| `HTTP_MAX_CONNS_PER_HOST` | `256` | **SET** |
| `MODEL_LIST_URL` | `""` | **SET** — prevents model list fetch |
| `STORAGE_TYPE` | `sqlite` | **SET** |
| `IDENTITY_ENABLED` | `false` | **SET** |
| `GUARDRAILS_ENABLED` | `false` | **SET** |
| `USAGE_ENABLED` | `false` | **SET** |
| `LOGGING_ENABLED` | `false` | **SET** |
| `METRICS_ENABLED` | `false` | **SET** |
| `SEMANTIC_CACHE_ENABLED` | `false` | **SET** |
| `RESPONSE_CACHE_SIMPLE_ENABLED` | `false` | **SET** |
| `TOKEN_SAVER_ENABLED` | `false` | **SET** |
| `SWAGGER_ENABLED` | `false` | **SET** |
| `ENABLE_ANTHROPIC_INGRESS` | `false` | **SET** |
| `CLI_TOOLS_ENABLED` | `false` | **SET** |
| `COMBOS_ENABLED` | `false` | **SET** |
| `ADMIN_ENDPOINTS_ENABLED` | `false` | **SET** |
| `ADMIN_UI_ENABLED` | `false` | **SET** |
| `PPROF_ENABLED` | `true` (Linux) / `false` (Windows) | **Differs** |

### `aurora-default` (Baseline — No Tuning)

**Linux** (`linux/competitors/aurora-default.sh`) and **Windows** (`windows/competitors/aurora-default.ps1`):

| Variable | Value | Status |
|----------|-------|--------|
| `PORT` | from parameter | SET |
| `OPENAI_BASE_URL` | from mock URL | SET |
| `OPENAI_API_KEY` | from api key | SET |
| `AURORA_MASTER_KEY` | from api key | SET |
| Everything else | **NOT SET** | **Relies on code defaults** |

**Windows note:** FairnessNotes say "Usage tracking and request logging off via new code defaults" — this means the code itself defaults these to `false`, so even without explicit env vars, usage/logging are off. But **all other features are ON**: admin endpoints, admin UI, identity, body snapshot, swagger, CLI tools, combos, anthropic ingress, etc.

### `aurora-tuned` (Network Tuning Only)

**Linux** (`linux/competitors/aurora-tuned.sh`) and **Windows** (`windows/competitors/aurora-tuned.ps1`):

| Variable | Value | Status |
|----------|-------|--------|
| `AURORA_H2C_ENABLED` | `true` | **SET** |
| `HTTP_MAX_IDLE_CONNS` | `4096` | **SET** |
| `HTTP_MAX_IDLE_CONNS_PER_HOST` | `4096` | **SET** |
| `HTTP_MAX_CONNS_PER_HOST` | `256` | **SET** |
| Everything else | **NOT SET** | **Relies on code defaults** |

**Missing vs `aurora`:** No `AURORA_MINIMAL_BENCH_MODE`, no feature disables (guardrails, usage, logging, metrics, cache, token saver, admin, identity, swagger, CLI tools, combos, anthropic ingress).

### `aurora-docker` (Docker Only — Linux)

**Linux only** (`linux/competitors/aurora-docker.sh`):

Sets most feature disables but **missing**:
- `AURORA_MINIMAL_BENCH_MODE` — **NOT SET**
- `AURORA_H2C_ENABLED` — **NOT SET**
- `HTTP_MAX_IDLE_CONNS` — **NOT SET**
- `HTTP_MAX_IDLE_CONNS_PER_HOST` — **NOT SET**
- `HTTP_MAX_CONNS_PER_HOST` — **NOT SET**
- `MODEL_LIST_URL` — **NOT SET**
- `STORAGE_TYPE` — **NOT SET**
- `IDENTITY_ENABLED` — **NOT SET**
- `ENABLE_ANTHROPIC_INGRESS` — **NOT SET**

---

## 2. Gap Analysis: What's Missing for Max Throughput

### Critical Gaps (causing performance loss)

| Missing Variable | In Variant | Impact |
|------------------|------------|--------|
| **`AURORA_CHAT_FAST_PATH_PASSTHROUGH=true`** | ALL variants | **BIGGEST GAP** — bypasses JSON decode/re-encode entirely. Estimated 15-20% throughput improvement. The code at `translated_inference_service.go:547-550` checks this env var but NO competitor sets it. |
| **`PROMPT_CACHE_MODE=off`** | ALL variants | Prompt cache breakpoint injection runs on every request even when no provider supports it for the mock. Small but nonzero overhead. |
| **`DISABLE_REQUEST_BODY_SNAPSHOT=true`** | ALL variants (covered by `AURORA_MINIMAL_BENCH_MODE` only in `aurora` variant) | The `aurora-tuned` and `aurora-default` variants do NOT set this, so body snapshot + gjson parsing runs on every request (~3% CPU). |

### Medium Gaps

| Missing Variable | In Variant | Impact |
|------------------|------------|--------|
| `DISABLE_REQUEST_LOGGING=true` | Only in `aurora` via `AURORA_MINIMAL_BENCH_MODE` | `aurora-tuned` and `aurora-default` still run request logger middleware |
| `IDENTITY_ENABLED=false` | Only in `aurora` | `aurora-tuned` and `aurora-default` run identity/auth checks |
| `ADMIN_ENDPOINTS_ENABLED=false` | Only in `aurora` | Admin route registration overhead |
| `ADMIN_UI_ENABLED=false` | Only in `aurora` | Static file serving overhead |
| `CLI_TOOLS_ENABLED=false` | Only in `aurora` | CLI tool route registration |
| `COMBOS_ENABLED=false` | Only in `aurora` | Combo model resolution overhead |
| `ENABLE_ANTHROPIC_INGRESS=false` | Only in `aurora` | Anthropic-specific route registration |
| `SWAGGER_ENABLED=false` | Only in `aurora` | Swagger UI overhead |
| `MODEL_LIST_URL=""` | Only in `aurora` | Model list fetch on startup (not per-request, but startup cost) |

### Already Correctly Handled

| Variable | Status |
|----------|--------|
| `GUARDRAILS_ENABLED=false` | Code defaults to `false` — OK |
| `USAGE_ENABLED=false` | Code defaults to `false` — OK |
| `LOGGING_ENABLED=false` | Code defaults to `false` — OK |
| `METRICS_ENABLED=false` | Code defaults to `false` — OK |
| `SEMANTIC_CACHE_ENABLED=false` | Code defaults to `false` — OK |
| `RESPONSE_CACHE_SIMPLE_ENABLED=false` | Code defaults to `false` — OK |
| `TOKEN_SAVER_ENABLED=false` | Code defaults to `false` — OK |

---

## 3. Exact Variables for Maximum THROUGHPUT

### For `aurora` competitor (already optimal, add fast path):

```bash
# Already set in aurora.sh / aurora.ps1:
AURORA_MINIMAL_BENCH_MODE=true
AURORA_H2C_ENABLED=true
HTTP_MAX_IDLE_CONNS=4096
HTTP_MAX_IDLE_CONNS_PER_HOST=4096
HTTP_MAX_CONNS_PER_HOST=256
MODEL_LIST_URL=""
STORAGE_TYPE=sqlite
IDENTITY_ENABLED=false
GUARDRAILS_ENABLED=false
USAGE_ENABLED=false
LOGGING_ENABLED=false
METRICS_ENABLED=false
SEMANTIC_CACHE_ENABLED=false
RESPONSE_CACHE_SIMPLE_ENABLED=false
TOKEN_SAVER_ENABLED=false
SWAGGER_ENABLED=false
ENABLE_ANTHROPIC_INGRESS=false
CLI_TOOLS_ENABLED=false
COMBOS_ENABLED=false
ADMIN_ENDPOINTS_ENABLED=false
ADMIN_UI_ENABLED=false

# MISSING — add these:
AURORA_CHAT_FAST_PATH_PASSTHROUGH=true    # Biggest single win
PROMPT_CACHE_MODE=off                     # Skip prompt cache injection
DISABLE_REQUEST_BODY_SNAPSHOT=true        # Already covered by MINIMAL_BENCH_MODE, but explicit is safer
```

### For `aurora-tuned` competitor (needs full feature disables):

```bash
# Already set in aurora-tuned.sh / aurora-tuned.ps1:
AURORA_H2C_ENABLED=true
HTTP_MAX_IDLE_CONNS=4096
HTTP_MAX_IDLE_CONNS_PER_HOST=4096
HTTP_MAX_CONNS_PER_HOST=256

# MISSING — add these:
AURORA_MINIMAL_BENCH_MODE=true            # Disables logging + body snapshot + usage
AURORA_CHAT_FAST_PATH_PASSTHROUGH=true    # Biggest single win
PROMPT_CACHE_MODE=off                     # Skip prompt cache injection
GUARDRAILS_ENABLED=false
USAGE_ENABLED=false
LOGGING_ENABLED=false
METRICS_ENABLED=false
SEMANTIC_CACHE_ENABLED=false
RESPONSE_CACHE_SIMPLE_ENABLED=false
TOKEN_SAVER_ENABLED=false
SWAGGER_ENABLED=false
ENABLE_ANTHROPIC_INGRESS=false
CLI_TOOLS_ENABLED=false
COMBOS_ENABLED=false
ADMIN_ENDPOINTS_ENABLED=false
ADMIN_UI_ENABLED=false
IDENTITY_ENABLED=false
MODEL_LIST_URL=""
STORAGE_TYPE=sqlite
```

### For `aurora-default` competitor (needs everything):

```bash
# Already set in aurora-default.sh / aurora-default.ps1:
PORT, OPENAI_BASE_URL, OPENAI_API_KEY, AURORA_MASTER_KEY

# MISSING — add these for fair comparison:
AURORA_MINIMAL_BENCH_MODE=true
AURORA_H2C_ENABLED=true
HTTP_MAX_IDLE_CONNS=4096
HTTP_MAX_IDLE_CONNS_PER_HOST=4096
HTTP_MAX_CONNS_PER_HOST=256
AURORA_CHAT_FAST_PATH_PASSTHROUGH=true
PROMPT_CACHE_MODE=off
MODEL_LIST_URL=""
STORAGE_TYPE=sqlite
IDENTITY_ENABLED=false
GUARDRAILS_ENABLED=false
USAGE_ENABLED=false
LOGGING_ENABLED=false
METRICS_ENABLED=false
SEMANTIC_CACHE_ENABLED=false
RESPONSE_CACHE_SIMPLE_ENABLED=false
TOKEN_SAVER_ENABLED=false
SWAGGER_ENABLED=false
ENABLE_ANTHROPIC_INGRESS=false
CLI_TOOLS_ENABLED=false
COMBOS_ENABLED=false
ADMIN_ENDPOINTS_ENABLED=false
ADMIN_UI_ENABLED=false
```

---

## 4. Platform Differences

### Linux vs Windows

| Aspect | Linux | Windows |
|--------|-------|---------|
| `PPROF_ENABLED` | `true` in `aurora` | `false` in `aurora` |
| Profiling | curl pprof during benchmark (compare.sh:104-128) | **No pprof collection** in compare.ps1 |
| Process management | `kill $PID` | `Stop-Process -Id $pid -Force` |
| Binary path | `bin/linux/aurora-bench` | `bin\windows\aurora-bench.exe` |
| H2C support | Works natively | Works via `SO_CONDITIONAL_ACCEPT` always-on |
| Mock server | Same Go binary | Same Go binary |

### What Linux Has That Windows Doesn't

1. **pprof profiling during benchmark** — `compare.sh` lines 104-128 collect CPU/heap/goroutine/block/mutex profiles. `compare.ps1` does NOT collect any profiles.
2. **aurora-docker variant** — Docker-based competitor only on Linux.

### What Windows Has That Linux Doesn't

1. **`BenchmarkProfiling.psm1`** module — imported but not used in compare.ps1 flow.
2. **`aurora-standalone.ps1`** scenario — standalone benchmark with bifrost-benchmarking tool integration.

---

## 5. Why Performance Is Lower Than Expected

### Root Cause Analysis

| Issue | Evidence | Fix |
|-------|----------|-----|
| **Fast path never enabled** | `AURORA_CHAT_FAST_PATH_PASSTHROUGH` not set in ANY variant. Code at `translated_inference_service.go:547-550` checks this. | Add `AURORA_CHAT_FAST_PATH_PASSTHROUGH=true` |
| **Double JSON parse** | CPU profile shows 15% in JSON. `ChatRequest.UnmarshalJSON` does goccy/go-json Unmarshal + gjson ForEach for unknown fields. Body snapshot already did gjson peek. | Code optimization needed (see PERFORMANCE_ANALYSIS.md) |
| **Body snapshot on every request** | `aurora-tuned` and `aurora-default` don't set `AURORA_MINIMAL_BENCH_MODE` or `DISABLE_REQUEST_BODY_SNAPSHOT` | Add `AURORA_MINIMAL_BENCH_MODE=true` or `DISABLE_REQUEST_BODY_SNAPSHOT=true` |
| **Prompt cache injection** | `cache.prompt.mode` defaults to `"auto"` — injects `cache_control` markers on every request even for mock provider | Add `PROMPT_CACHE_MODE=off` |
| **Admin/identity/swagger overhead** | `aurora-tuned` and `aurora-default` don't disable these | Add `ADMIN_ENDPOINTS_ENABLED=false`, `IDENTITY_ENABLED=false`, etc. |
| **GC pressure** | 68 allocs/op, 5.8KB/op. CPU profile shows 25% in GC. | Reduce allocations via pooling (code change) |
| **No pprof on Windows** | Cannot diagnose CPU hotspots on Windows runs | Add pprof collection to `compare.ps1` |

### Estimated Impact

| Fix | Expected Improvement |
|-----|---------------------|
| `AURORA_CHAT_FAST_PATH_PASSTHROUGH=true` | **+15-20% throughput** |
| `AURORA_MINIMAL_BENCH_MODE=true` (for tuned/default) | **+5-10% throughput** |
| `PROMPT_CACHE_MODE=off` | **+1-2% throughput** |
| Feature disables (admin, identity, etc.) | **+2-3% throughput** |
| Code: eliminate double JSON parse | **+2-3% throughput** |
| Code: reduce allocations | **+1-2% throughput** |
| **Total estimated** | **+25-40% throughput** |

---

## 6. Recommended Action Items

### Immediate (env var changes only)

1. Add `AURORA_CHAT_FAST_PATH_PASSTHROUGH=true` to `aurora.sh`, `aurora.ps1`, `aurora-tuned.sh`, `aurora-tuned.ps1`
2. Add `PROMPT_CACHE_MODE=off` to all aurora variants
3. Add full feature disables to `aurora-tuned.sh` / `aurora-tuned.ps1`
4. Add `AURORA_MINIMAL_BENCH_MODE=true` to `aurora-docker.sh`

### Short-term (code changes)

1. Add pprof collection to `windows/scenarios/compare.ps1`
2. Optimize `ChatRequest.UnmarshalJSON` to avoid redundant gjson parse when body snapshot already extracted selectors

### Medium-term (code changes)

1. Implement `sync.Pool` for response buffers in `language_model_client`
2. Consider `json.MarshalNoEscape` for response writing
3. Tune `GOGC=200` or `GOMEMLIMIT` for throughput-over-latency workloads
