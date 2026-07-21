# Aurora Gateway Performance Analysis: Chokepoint Breakdown

Based on `aurora-bench/bench-results/linux/` — 60s benchmarks at 10,000 req/s target on 4-core machine.

## 1. Summary: Aurora vs Kong

| Metric | Aurora | Kong | Delta |
|--------|--------|------|-------|
| Throughput (rps) | 6,609 – 6,810 | 7,737 – 8,170 | **+1,037 to +1,561 rps** |
| Mean latency (ms) | 36.1 – 36.8 | 27.5 – 29.5 | **–6.6 to –9.3 ms** |
| P50 latency (ms) | 31.3 – 32.3 | 23.6 – 25.2 | –6.1 to –8.6 ms |
| P99 latency (ms) | 108.5 – 108.8 | 83.1 – 91.6 | –16.9 to –25.8 ms |
| Allocs/op | 68.1 | 75.5 | **+7.4 (Kong allocs more!)** |
| Bytes/op | 5,875 | 6,441 | **+566 (Kong uses more memory!)** |

**Kong is 15–24% faster despite allocating 11% more per request.** The bottleneck is not allocation volume — it's architectural overhead in Aurora's per-request processing.

## 2. CPU Profile: Where Time Goes (Aurora, 60s)

From `aurora.cpu.prof`: 89.44s total samples at 149% CPU utilization.

| Category | Flat Time | % | Primary Symbols |
|----------|-----------|---|-----------------|
| **Syscall (network I/O)** | 26.47s | **29.6%** | `Syscall6`, `syscall.Write`, `syscall.Read` |
| **GC** | 12.75s | **14.3%** | `mallocgc`, `newobject`, `gcAssistAlloc` |
| **HTTP request write** | 11.91s | **13.3%** | `(*Request).write` |
| **I/O copy** | 10.96s | **12.3%** | `io.copyBuffer` |
| **Runtime overhead** | 10.44s | **11.7%** | `runtime.systemstack`, `runtime.schedule` |
| **Middleware + handler** | ~20s | **~22%** | Echo chain + passthrough logic |
| **Response header write** | 1.65s | 1.8% | `(*chunkWriter).writeHeader` |

**Key insight: 67% of CPU is consumed by network I/O + data copying + GC.** The middleware logic itself accounts for only ~22% of samples.

## 3. Middleware Chain Cost Breakdown

### 3.1 Full Chain (outer → inner)

```
Echo.ServeHTTP                       34.12s (38.2%)
├── Recover middleware                32.79s
│   └── BodyLimit middleware          32.70s
│       └── Request ID (func3+func4)  30.00s
│           └── modelInteractionWriteDeadline  29.80s
│               └── RequestSnapshotCapture     29.40s
│                   └── PassthroughSemanticEnrichment  28.33s
│                       └── CapabilityGateMiddleware    28.20s
│                           └── AuthMiddleware          28.15s
│                               └── WorkflowResolution  27.42s
│                                   └── AuthKeyRateLimit 20.31s
│                                       └── ChatCompletion 20.20s
```

### 3.2 Incremental Per-Middleware Cost

| # | Middleware | Cumulative | Delta | % of Total | Notes |
|---|-----------|-----------|-------|-----------|-------|
| 0 | Echo routing + context setup | 34.12s | 1.33s | 1.5% | Path matching, method routing |
| 1 | Recover | 32.79s | 0.09s | 0.1% | Defers panic recovery — negligible |
| 2 | BodyLimit (10MB) | 32.70s | 0.20s | 0.2% | Wraps body in LimitedReader |
| 3 | **Request ID (func3+func4)** | 30.00s | **2.50s** | **2.8%** | UUID generation + body read triggers |
| 4 | WriteDeadline | 29.80s | 0.20s | 0.2% | SetWriteDeadline syscall |
| 5 | **RequestSnapshotCapture** | 29.40s | **0.40s** | **0.4%** | Full body read (≤64KB) + gjson parse |
| 6 | **PassthroughSemanticEnrichment** | 28.33s | **1.07s** | **1.2%** | Provider resolution for /p/ routes |
| 7 | CapabilityGate | 28.20s | 0.13s | 0.1% | Map lookup — negligible |
| 8 | AuthMiddleware | 28.15s | 0.05s | 0.1% | Key comparison — negligible in bench (master key) |
| 9 | **WorkflowResolution** | 27.42s | **0.73s** | **0.8%** | Model selector resolution, registry lookup |
| 10 | AuthKeyRateLimit | 20.31s | 0.02s | 0.0% | Rate limit check — essentially free here |
| 11 | **ChatCompletion → tryEarlyBench** | 20.05s | **0.15s** | **0.2%** | Fast-path passthrough dispatch |
| 12 | **Router.Passthrough (upstream call)** | 13.96s | — | **15.6%** | HTTP call to upstream provider |
| 13 | **proxyPassthroughResponse** | 5.02s | — | **5.6%** | Copy response back to client |

**Middleware overhead (items 0–11) totals ~6.5s or ~7% of CPU.** The remaining 93% is upstream I/O and GC.

## 4. Chokepoint Analysis

### Chokepoint #1: Dual Network I/O (29.6% CPU — PRIMARY BOTTLENECK)

**What**: Every request requires two full HTTP round trips:
1. Client → Aurora (read request body + headers)
2. Aurora → Upstream provider (forward request + read response)

29.6% of all CPU samples land in `Syscall6`. Combined with `(*Request).write` (13.3%) and `io.copyBuffer` (12.3%), **55% of CPU is pure I/O plumbing.**

**Why Kong wins**: Kong's nginx core is event-driven (epoll/kqueue) with zero-copy buffers and minimal per-request state. Go's net/http allocates a goroutine + buffers per connection, writes full request bytes with header serialization (`CanonicalMIMEHeaderKey` at 1.9% alone), and copies data through multiple buffer layers (bufio, chunked writer, persistConn).

### Chokepoint #2: GC Pressure (14.3% CPU)

**What**: Go's garbage collector consumes 14.3% of CPU. This includes:
- `runtime.mallocgc`: 14.3% cumulative
- `runtime.newobject`: 8.3%
- `gcAssistAlloc`: 4.5%
- GC drain/scan: ~3-5%

**Why it hurts**: Even though Aurora allocates *less* per op than Kong (68 vs 75 allocs, 5.9KB vs 6.4KB), Go's GC runs concurrently and competes for CPU. With 4 cores and 6,600 rps, GC is allocating ~39 MB/s. The GC assist mechanism forces mutator goroutines to help with GC before they can allocate, directly adding latency to the request path.

### Chokepoint #3: Request Body Copy + Multiple JSON Parses

**What**: The same request body is read/re-parsed multiple times:
1. **Request ID middleware** (func4): reads body to compute ID (triggers buffering)
2. **RequestSnapshotCapture**: reads full body (up to 64KB), stores it, parses with gjson for `model`/`provider`/`stream` hints
3. **WorkflowResolution**: falls back to gjson re-parse if hints weren't cached from step 2
4. **ChatCompletion handler**: full `encoding/json.Unmarshal` of the request

**Cost**: Each body read allocates a buffer (up to 64KB), copies bytes, and triggers GC. The heap profile shows `io.ReadAll` holding 14-18% of heap at steady state. `encoding/json` operations consume ~23% of heap during model loading.

### Chokepoint #4: HTTP Request Serialization (13.3% CPU)

**What**: `net/http.(*Request).write` serializes the entire HTTP request (method, path, headers, body) into bytes for the upstream connection. This includes:
- `Header.writeSubset`: 1.6% (iterates all headers, sorts, formats)
- `transferWriter.writeBody`: 9.4% (chunked encoding + body copy)
- `CanonicalMIMEHeaderKey`: 1.9% (header key canonicalization)

**Why**: Go's HTTP client serializes the full request on every call rather than maintaining a zero-copy buffer pool. For a reverse proxy doing 6,600 req/s, this is expensive — every request re-serializes the same headers.

### Chokepoint #5: Goroutine Scheduling Overhead (11.7% CPU)

**What**: `runtime.systemstack` (11.7%) and `runtime.schedule` (2.1%) represent Go scheduler overhead. With hundreds of goroutines blocked on network I/O, the scheduler spends significant time:
- `findRunnable`: 1.2%
- `schedule`: 2.1%
- Goroutine parking/waking: 1.9%

**Goroutine profile** shows 302 goroutines parked, of which 147 (49%) are waiting on network `Read`. The rest are in `selectgo` (channel operations) and poll loops. This is the Go runtime managing concurrent I/O — Kong/nginx avoids this entirely with an event loop model.

## 5. Request Flow: Full Path Through Aurora

```
                                        COST
                                        (cumulative)
CLIENT ──► Echo.ServeHTTP             34.12s
             │
             ▼
           Recover middleware          32.79s   ← panic recovery wrapper
             │
             ▼
           BodyLimit middleware         32.70s   ← wraps body in LimitedReader
             │
             ▼
           Request ID middleware        30.00s   ← UUID gen + set X-Request-ID
             │                                      for bench: sequential integer
             ▼
           WriteDeadline middleware     29.80s   ← SetWriteDeadline for streaming
             │
             ▼
           RequestSnapshotCapture       29.40s   ← BODY READ: up to 64KB into memory
             │                                      gjson parse for model/provider/stream
             ▼
           PassthroughSemanticEnrichment 28.33s   ← provider enrichment for /p/ routes
             │
             ▼
           CapabilityGateMiddleware     28.20s   ← edition gating (map lookup)
             │
             ▼
           AuthMiddleware               28.15s   ← master key / JWT / API key check
             │                                      bench: master key → fast path
             ▼
           WorkflowResolution            27.42s   ← model selector resolution
             │                                      registry lookup, policy check
             ▼
           AuthKeyRateLimitMiddleware    20.31s   ← in-memory rate limiter check
             │
             ▼
           ChatCompletion handler        20.20s   ← tryEarlyBenchChatPassthrough
             │
             ▼
           Router.Passthrough            13.96s   ← upstream HTTP call
             │
             ▼
           proxyPassthroughResponse      5.02s    ← copy response to client
             │
CLIENT ◄─── Response body
```

## 6. Recommendations

### High Impact
1. **Body read deduplication**: The body is read 3× (RequestID, Snapshot, handler). Cache the read body after the first read and reuse it. Currently, body ≤64KB is captured but then re-read in the handler anyway.
2. **HTTP transport pooling**: Tune `MaxIdleConns` and `MaxIdleConnsPerHost` on the upstream transport. The profile shows `tryPutIdleConn` at 1.1% — connection management overhead.
3. **Eliminate redundant gjson parses**: `RequestSnapshotCapture` already parses the body for hints. `WorkflowResolution` should never re-parse. Ensure the hints are always propagated through the context.

### Medium Impact
4. **Switch to fasthttp or custom server**: Echo v5 adds middleware overhead (applyMiddleware at 1.0%). A raw `net/http` handler or custom router would reduce this.
5. **Reduce body snapshot size**: 64KB is overly generous for JSON chat requests (~1KB typical). Reducing this threshold reduces per-request memory pressure.
6. **Audit log bypass in bench mode**: If audit logging is configured but bench mode is active, skip body capture entirely.

### Low Impact
7. **Header pre-serialization**: Pre-serialize common upstream headers into a reusable buffer per connection.
8. **Pool HTTP request objects**: Use `sync.Pool` for `http.Request` objects sent upstream.
9. **Consider Go 1.24+ alloc optimizations**: The profile shows significant `runtime.newobject` for small structs — newer Go versions reduce these.

## 7. Raw Benchmark Data

### Aurora standalone (bench results)
| Metric | Run 1 | Run 2 |
|--------|-------|-------|
| Throughput (rps) | 6,388 | 6,810 |
| Mean latency (ms) | 38.2 | 35.6 |
| Allocs/op | 70.0 | 68.0 |
| Bytes/op | 5,954 | 5,860 |

### Aurora vs Kong (side-by-side)
| Metric | Aurora | Kong | Advantage |
|--------|--------|------|-----------|
| Throughput (rps) | 6,609 | 8,170 | **Kong +23.6%** |
| Mean latency (ms) | 36.8 | 27.5 | Kong -25.3% |
| P99 latency (ms) | 108.8 | 83.1 | Kong -23.7% |
| Allocs/op | 68.1 | 75.5 | **Aurora -9.8%** |
| Bytes/op | 5,875 | 6,441 | **Aurora -8.8%** |

Despite allocating 9-10% less memory per request, Aurora is 23.6% slower — confirming the bottleneck is **not allocation volume but I/O handling overhead and per-request processing**.
