# Aurora Benchmark Framework

Compare AI gateways with reproducible results. Supports 16 gateways: Aurora, Bifrost, LiteLLM, Kong, APISIX, Portkey, Helicone, New API, GoModel, and variants.

## Fresh Machine Setup

What you need to install on a brand-new Windows machine to run benchmarks.

### 1. Essential (always required)

| Tool | Why | Install |
|------|-----|---------|
| **Git** | Clone this repo | `winget install Git.Git` |
| **Go 1.26+** | Build mock server + benchmark CLI from source | `winget install GoLang.Go` or [go.dev/dl](https://go.dev/dl/) |
| **PowerShell 5.1+** | Runs all benchmark scripts | Built into Windows 10/11 |

### 2. Per-competitor dependencies

| Competitor | Requires | Install |
|------------|----------|---------|
| `aurora` | — | Binary auto-downloaded from [releases](https://github.com/aurorallm/aurora/releases) |
| `aurora-default` | — | Shares binary with `aurora` |
| `aurora-tuned` | — | Shares binary with `aurora` |
| `bifrost` | **Node.js** | `winget install OpenJS.NodeJS` or [nodejs.org](https://nodejs.org/) |
| `litellm` | **Python 3.x + pip** | `winget install Python.Python.3.12` or [python.org](https://python.org/) |
| `portkey` | **Node.js** | `winget install OpenJS.NodeJS` |
| `gomodel-native` | — | Binary auto-downloaded from [releases](https://github.com/ENTERPILOT/GoModel/releases) |
| `new-api-native` | — | Binary auto-downloaded from [releases](https://github.com/QuantumNous/new-api/releases) |
| `helicone-native` | **Linux/WSL** | Binary auto-downloaded from [releases](https://github.com/Helicone/ai-gateway/releases) (Linux only) |
| `aurora-docker` | **Docker Desktop** | `winget install Docker.DockerDesktop` |
| `gomodel` | **Docker Desktop** | Same as above |
| `helicone` | **Docker Desktop** | Same as above |
| `kong` | **Docker Desktop** | Same as above |
| `apisix` | **Docker Desktop** | Same as above |
| `new-api` | **Docker Desktop** | Same as above |

### 3. Quick install (all at once)

```powershell
# Core
winget install Git.Git
winget install GoLang.Go

# Optional per-competitor
winget install OpenJS.NodeJS      # bifrost, portkey
winget install Python.Python.3.12  # litellm
winget install Docker.DockerDesktop  # Docker-based competitors
```

### 4. Verify

```powershell
git --version
go version
npx --version    # if Node.js installed
python --version # if Python installed
docker --version # if Docker installed
```

## Get the repo

```powershell
git clone https://github.com/aurorallm/bench.git
cd bench
```

## What gets built vs downloaded

| Binary | Source | How |
|--------|--------|-----|
| `bin/mock-server.exe` | `mock-server/main.go` | Built from source with `go build` |
| `bin/aurora-bench-cli.exe` | `tools/benchmark-cli/main.go` + `internal/benchmark/` | Built from source with `go build` |
| `bin/aurora-bench.exe` | [aurorallm/aurora](https://github.com/aurorallm/aurora) | Auto-downloaded from releases |
| `bin/gomodel.exe` | [ENTER PILOT/GoModel](https://github.com/ENTERPILOT/GoModel) | Auto-downloaded from releases |
| `bin/helicone-gateway` | [Helicone/ai-gateway](https://github.com/Helicone/ai-gateway) | Auto-downloaded from releases (Linux) |
| `bin/new-api.exe` | [QuantumNous/new-api](https://github.com/QuantumNous/new-api) | Auto-downloaded from releases |

## What is the Mock Server?

The mock server (`mock-server/main.go`) is a lightweight Go HTTP server that mimics the OpenAI API. It:

- **Responds instantly** with deterministic payloads — no network latency, no real AI inference
- **Returns configurable models** — set `MOCK_MODELS=gpt-4o,claude-sonnet` env var
- **Endpoints:** `/v1/chat/completions`, `/v1/responses`, `/v1/models`, `/health`
- **Deterministic content:** 25 prompt tokens echoed back + 35 completion tokens (stream + non-stream)
- **Why:** All gateways point to the same mock upstream. This measures **pure gateway overhead** — not provider latency. Without it, each benchmark run would cost real API money and results would be noisy.

All gateways (Aurora, Bifrost, LiteLLM, etc.) are configured to send traffic to `http://127.0.0.1:{mockPort}` instead of a real provider like OpenAI.

## Quick Start

```powershell
.\run.ps1 -List                          # Show available gateways
.\run.ps1 -Clean -Competitors aurora     # Build mock + CLI, benchmark Aurora
.\run.ps1 -Competitors aurora            # Use pre-built binaries
.\run.ps1 -Competitors aurora,bifrost,litellm -Mode smoke  # Quick 3-way
.\run.ps1 -Competitors aurora -Mode publish               # Publish-grade
```

## Commands

### run.ps1

| Flag | Default | Description |
|------|---------|-------------|
| `-Competitors` | `aurora` | Comma-separated names |
| `-Mode` | `auto` | `smoke` (500/30s), `publish` (5000/60s), `auto` (4000/120s) |
| `-Rate` | auto | Requests/sec |
| `-Duration` | auto | Seconds |
| `-MockPort` | 9099 | Mock server port |
| `-Model` | `gpt-4o-mini` | Model name in payload |
| `-Concurrency` | 256 | Workers |
| `-ApiKey` | `sk-bench-test-key` | Auth token |
| `-Clean` | off | Rebuild mock + CLI from source |
| `-List` | off | Show available competitors |
| `-Help` | off | Show full help |

### build.ps1

| Flag | Default | Description |
|------|---------|-------------|
| `-Clean` | off | Delete old binaries before building |
| `-Run` | off | Auto-start benchmark after build |

## Competitors (16)

| Name | Type | Port | Source |
|------|------|------|--------|
| `aurora` | binary | 8081 | [aurorallm/aurora](https://github.com/aurorallm/aurora) releases |
| `aurora-default` | binary | 8081 | Same binary, default config |
| `aurora-tuned` | binary | 8081 | Same binary, h2c + pool tuning |
| `aurora-docker` | docker | 8082 | `aurorahq/aurora:latest` |
| `bifrost` | npx | 8080 | `npx @maximhq/bifrost` |
| `gomodel` | docker | 8091 | `enterpilot/gomodel:latest` |
| `gomodel-native` | binary | 8091 | [GoModel releases](https://github.com/ENTERPILOT/GoModel/releases) |
| `helicone` | docker | 8585 | `helicone/ai-gateway` |
| `helicone-native` | binary | 8585 | [Helicone releases](https://github.com/Helicone/ai-gateway/releases) (Linux) |
| `kong` | docker | 8000 | `kong:latest` |
| `apisix` | docker | 9080 | `apache/apisix` |
| `litellm` | pip | 8082 | `pip install litellm[proxy]` |
| `new-api` | docker | 3001 | `calciumion/new-api` |
| `new-api-native` | binary | 3001 | [New API releases](https://github.com/QuantumNous/new-api/releases) |
| `portkey` | npx | 8787 | `npx @portkey-ai/gateway` |

## Structure

```
bench/
├── run.ps1                       # Entry point
├── build.ps1                     # Build mock + CLI from Go source
├── generate-dashboard.ps1        # HTML dashboard generator
├── go.mod                        # Go module for benchmark CLI
├── .gitignore
├── README.md
│
├── bin/                          # Binaries (built or downloaded)
│   ├── mock-server.exe           # Built from source
│   ├── aurora-bench-cli.exe      # Built from source
│   ├── aurora-bench.exe          # Downloaded from releases
│   ├── gomodel.exe               # Downloaded from releases
│   ├── helicone-gateway          # Downloaded from releases (Linux)
│   ├── new-api.exe               # Downloaded from releases
│   └── data/aurora.db
│
├── internal/benchmark/           # Vendored Go benchmark engine
│   ├── loadtest.go               # Core load tester (stdlib only)
│   ├── timer.go                  # POSIX high-res timer
│   └── timer_windows.go          # Windows QPC timer
│
├── competitors/                  # 16 gateway definitions
│   ├── aurora.ps1, bifrost.ps1, litellm.ps1, kong.ps1, ...
│   └── _template.ps1
│
├── scenarios/
│   ├── compare.ps1               # N-gateway comparison (main entry)
│   ├── aurora-standalone.ps1     # Aurora-only
│   └── bifrost-side-by-side.ps1  # 3-way comparison
│
├── modules/
│   ├── BenchmarkUtilities.psm1       # Health checks, preflight, warmup
│   ├── BenchmarkInfrastructure.psm1  # Build mock, run benchmarks, verify
│   ├── BenchmarkComparison.psm1      # Parse results, comparison JSON
│   └── BenchmarkProfiling.psm1       # pprof capture
│
├── tools/
│   ├── benchmark-cli/main.go     # Benchmark CLI source
│   ├── generate_benchmark_artifacts.py  # Chart generation
│   └── test_generate_benchmark_artifacts.py
│
├── mock-server/                  # Mock OpenAI backend source
│   ├── main.go, go.mod, build.ps1
│
├── configs/                      # Gateway config templates
│   ├── aurora-bench.yaml, bifrost-config.json, litellm-config.yaml, ...
│   └── env.template
│
└── bench-results/                # Generated results (gitignored)
```

## How It Works

1. **Build** — `build.ps1` compiles mock server + benchmark CLI from Go source (stdlib only, no external deps)
2. **Download** — competitor Install scripts auto-download gateway binaries from GitHub releases if not present
3. **Mock server** starts — deterministic OpenAI-compatible backend on configurable port
4. **Gateways** tested **sequentially** — one at a time, each gets full machine resources
5. **Benchmark CLI** uses QPC-precision timers (nanosecond latency on Windows)
6. **Comparison JSON** generated with all results + pairwise deltas

## Adding a Gateway

```powershell
copy competitors\_template.ps1 competitors\mygw.ps1
# Fill in Install + Start scriptblocks
.\run.ps1 -Competitors aurora,mygw
```

## Output

Results in `bench-results/{gateway1-vs-gateway2}/`:

```
bench-results/aurora-vs-bifrost/
├── 20260622-180657.aurora.json       # Raw result
├── 20260622-180657.bifrost.json
├── 20260622-180657.comparison.json   # Combined + deltas
└── *.log                             # Server output
```

Generate an interactive HTML dashboard:
```powershell
.\generate-dashboard.ps1
```

## Methodology

- Sequential testing (no resource contention)
- Same mock upstream for all gateways
- Auth enabled on all gateways
- Non-essential features disabled (logging, caching, budgets)
- Metrics: throughput, P50–P999 latency, success rate, allocs/op, bytes/op
