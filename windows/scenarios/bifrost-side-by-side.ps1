param(
    [string]$BenchmarkRepo = "",
    [string]$BenchmarkUrl = "https://github.com/maximhq/bifrost-benchmarking.git",
    [string]$ResultsDir = "bench-results\bifrost-side-by-side",
    [int]$BifrostPort = 8080,
    [int]$AuroraPort = 8081,
    [int]$LiteLLMPort = 8082,
    [int]$Rate = 500,
    [int]$Duration = 10,
    [int]$Timeout = 300,
    [string]$Model = "openai/gpt-4o-mini",
    [string]$Path = "chat/completions",
    [string]$Suffix = "v1",
    [int]$WarmupRequests = 25,
    [int]$PrewarmRequests = 0,
    [int]$PrewarmConcurrency = 64,
    [switch]$BigPayload,
    [switch]$StartAurora,
    [switch]$CaptureAuroraProfiles,
    [string]$AuroraUpstreamBaseUrl = "",
    [string]$AuroraUpstreamApiKey = "sk-bench-test-key",
    [switch]$NewWindow,
    [switch]$StartMock,
    [int]$MockPort = 9099,
    [string]$MockExePath = "",
    [switch]$StartBifrost,
    [string]$BifrostExePath = "",
    [string]$BifrostAppDir = "",
    [switch]$StartLiteLLM,
    [string]$LiteLLMCommand = "litellm",
    [string]$LiteLLMConfigPath = ""
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $PSCommandPath

# Resolve temp workspace for benchmark repo
if ([string]::IsNullOrEmpty($BenchmarkRepo)) {
    $tempBase = if ($env:OPENCODE_TEMP) { $env:OPENCODE_TEMP } else { Join-Path $env:TEMP "opencode" }
    $BenchmarkRepo = Join-Path $tempBase "bifrost-benchmarking"
}
$benchDir = Split-Path -Parent $scriptPath
$modulesPath = Join-Path $benchDir "modules"

Import-Module (Join-Path $modulesPath "BenchmarkUtilities.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkInfrastructure.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkProfiling.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkComparison.psm1") -Force

$repoRoot = $benchDir
$resolvedResultsDir = Join-Path $repoRoot $ResultsDir
New-Item -ItemType Directory -Force -Path $resolvedResultsDir | Out-Null

Ensure-BenchmarkRepo -BenchmarkRepo $BenchmarkRepo -BenchmarkUrl $BenchmarkUrl
$benchmarkExe = Ensure-BenchmarkBinary -BenchmarkRepo $BenchmarkRepo
Ensure-BenchmarkEnv -BenchmarkRepo $BenchmarkRepo -BifrostPort $BifrostPort -ApiKey $AuroraUpstreamApiKey

function Run-GatewayBenchmark {
    param([string]$Name, [int]$Port, [string]$OutPath, [string]$PrewarmOutPath)

    # Prewarm uses same CLI for consistency (light payload)
    if ($PrewarmRequests -gt 0) {
        Invoke-AuroraBench -Name "${Name} (prewarm)" -Port $Port -OutputPath $PrewarmOutPath `
            -Rate $Rate -Duration 10 -Concurrency $PrewarmConcurrency -Model $Model -Path "${Suffix}/${Path}" `
            -Auth $AuroraUpstreamApiKey -Warmup 0 -BenchDir $benchDir
    }

    # Main benchmark with full precision (QPC timer)
    Invoke-AuroraBench -Name $Name -Port $Port -OutputPath $OutPath `
        -Rate $Rate -Duration $Duration -Concurrency 256 -Model $Model -Path "${Suffix}/${Path}" `
        -Auth $AuroraUpstreamApiKey -Warmup $WarmupRequests -BenchDir $benchDir
}

$mockProc = $null
try {
    # ============================================================
    # 1. Start mock server (shared across both gateway tests)
    # ============================================================
    if ($StartMock) {
        $mockBinary = if ($MockExePath -ne "") { $MockExePath } else { Join-Path $benchDir "bin\mock-server.exe" }
        if (-not (Test-Path $mockBinary)) {
            Write-Host "Building mock server..." -ForegroundColor Yellow
            Push-Location (Join-Path $benchDir "mock-server")
            try { go build -o $mockBinary ./main.go } finally { Pop-Location }
        }
        Write-Host "Starting mock server on port $MockPort..." -ForegroundColor Cyan
        if ($NewWindow) {
            $mockProc = Start-MockServer -ExePath $mockBinary -Port $MockPort -Title "Mock Server ($MockPort)" -NewWindow
        } else {
            $mockProc = Start-MockServer -ExePath $mockBinary -Port $MockPort
        }
        Wait-ForHealth -Name "Mock Server" -Port $MockPort -TimeoutSeconds 15 -HealthPath "health"
    }

    # Track which gateways we'll test
    $gateways = @()
    if ($StartBifrost) { $gateways += "bifrost" }
    if ($StartLiteLLM) { $gateways += "litellm" }
    if ($StartAurora) { $gateways += "aurora" }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $auroraProfiles = $null

    # ============================================================
    # 2. Test each gateway SEQUENTIALLY — only one gateway runs at a time
    #    so each gets the full machine resources.
    # ============================================================
    foreach ($gw in $gateways) {
        Write-Host ""
        Write-Host ("=" * 70)
        Write-Host "  Testing gateway: $gw"
        Write-Host ("=" * 70)

        if ($gw -eq "bifrost") {
            if ($BifrostExePath -eq "") { throw "-StartBifrost requires -BifrostExePath" }
            if ($BifrostAppDir -eq "") { throw "-StartBifrost requires -BifrostAppDir" }
            if (-not (Test-Path $BifrostAppDir)) { New-Item -ItemType Directory -Path $BifrostAppDir -Force | Out-Null }

            Write-Host "Starting Bifrost on port $BifrostPort..." -ForegroundColor Cyan
            if ($NewWindow) {
                $proc = Start-BifrostGateway -ExePath $BifrostExePath -Port $BifrostPort -BifrostAppDir $BifrostAppDir -Title "Bifrost ($BifrostPort)" -NewWindow
            } else {
                $proc = Start-BifrostGateway -ExePath $BifrostExePath -Port $BifrostPort -BifrostAppDir $BifrostAppDir
            }
            Wait-ForHealth -Name "Bifrost" -Port $BifrostPort -TimeoutSeconds 60

            # Preflight + warmup
            Invoke-Preflight -Name "Bifrost" -Port $BifrostPort -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey
            Invoke-Warmup -Name "Bifrost" -Port $BifrostPort -WarmupRequests $WarmupRequests -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey

            # Benchmark
            $bifrostOut = Join-Path $resolvedResultsDir "$timestamp.bifrost.json"
            $bifrostPrewarmOut = Join-Path $resolvedResultsDir "$timestamp.bifrost.prewarm.json"
            Run-GatewayBenchmark -Name "Bifrost" -Port $BifrostPort -OutPath $bifrostOut -PrewarmOutPath $bifrostPrewarmOut

            # Stop Bifrost
            if ($proc -and -not $proc.HasExited) {
                Write-Host "Stopping Bifrost..." -ForegroundColor DarkYellow
                Stop-Process -Id $proc.Id -Force
                $proc = $null
            }

            # Cooldown gap — let OS free ports, TCP TIME_WAIT drain, etc.
            Write-Host "Cooldown $(5)s between gateway tests..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds 5
        }

        if ($gw -eq "litellm") {
            $litellmCfgPath = if ($LiteLLMConfigPath -ne "") { $LiteLLMConfigPath } else { Join-Path $benchDir "configs\litellm-config.yaml" }
            Write-Host "Starting LiteLLM on port $LiteLLMPort..." -ForegroundColor Cyan
            if ($NewWindow) {
                $proc = Start-LiteLLMGateway -Command $LiteLLMCommand -Port $LiteLLMPort -ConfigPath $litellmCfgPath -Title "LiteLLM ($LiteLLMPort)" -NewWindow
            } else {
                $proc = Start-LiteLLMGateway -Command $LiteLLMCommand -Port $LiteLLMPort -ConfigPath $litellmCfgPath
            }
            Wait-ForHealth -Name "LiteLLM" -Port $LiteLLMPort -TimeoutSeconds 60 -HealthPath "health/liveliness"

            # Preflight + warmup
            Invoke-Preflight -Name "LiteLLM" -Port $LiteLLMPort -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey
            Invoke-Warmup -Name "LiteLLM" -Port $LiteLLMPort -WarmupRequests $WarmupRequests -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey

            # Benchmark
            $litellmOut = Join-Path $resolvedResultsDir "$timestamp.litellm.json"
            $litellmPrewarmOut = Join-Path $resolvedResultsDir "$timestamp.litellm.prewarm.json"
            Run-GatewayBenchmark -Name "LiteLLM" -Port $LiteLLMPort -OutPath $litellmOut -PrewarmOutPath $litellmPrewarmOut

            # Stop LiteLLM
            if ($proc -and -not $proc.HasExited) {
                Write-Host "Stopping LiteLLM..." -ForegroundColor DarkYellow
                Stop-Process -Id $proc.Id -Force
                $proc = $null
            }

            Write-Host "Cooldown $(5)s between gateway tests..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds 5
        }

        if ($gw -eq "aurora") {
            if ($AuroraUpstreamBaseUrl -eq "") {
                throw "-StartAurora requires -AuroraUpstreamBaseUrl"
            }

            $auroraExe = Join-Path $benchDir "bin\aurora-bench.exe"
            if (-not (Test-Path $auroraExe)) {
                Write-Host "WARNING: Aurora binary not found at $auroraExe. Build it from the aurora repo." -ForegroundColor Yellow
                throw "Aurora binary not found. Build from aurora source: go build -o $auroraExe ./apps/aurora"
            }

            $auroraLog = Join-Path $resolvedResultsDir "aurora-server.log"
            Write-Host "Starting Aurora on port $AuroraPort..." -ForegroundColor Cyan
            if ($NewWindow) {
                $proc = Start-AuroraBenchServer -ExePath $auroraExe -Port $AuroraPort `
                    -UpstreamBaseUrl $AuroraUpstreamBaseUrl -UpstreamApiKey $AuroraUpstreamApiKey -LogPath $auroraLog -NewWindow
            } else {
                $proc = Start-AuroraBenchServer -ExePath $auroraExe -Port $AuroraPort `
                    -UpstreamBaseUrl $AuroraUpstreamBaseUrl -UpstreamApiKey $AuroraUpstreamApiKey -LogPath $auroraLog
            }
            Wait-ForHealth -Name "Aurora" -Port $AuroraPort -TimeoutSeconds 30

            # Preflight + warmup
            Invoke-Preflight -Name "Aurora" -Port $AuroraPort -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey
            Invoke-Warmup -Name "Aurora" -Port $AuroraPort -WarmupRequests $WarmupRequests -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey

            # Optional pprof capture
            if ($CaptureAuroraProfiles) {
                try {
                    Invoke-WebRequest -Uri "http://127.0.0.1:$AuroraPort/debug/pprof/" -UseBasicParsing -TimeoutSec 5 | Out-Null
                    $auroraProfiles = Start-PprofCapture -Port $AuroraPort -OutputPrefix (Join-Path $resolvedResultsDir "$timestamp.aurora") -Seconds $Duration
                    Start-Sleep -Milliseconds 500
                }
                catch {
                    Write-Warning "Aurora pprof endpoint is not reachable."
                }
            }

            # Benchmark
            $auroraOut = Join-Path $resolvedResultsDir "$timestamp.aurora.json"
            $auroraPrewarmOut = Join-Path $resolvedResultsDir "$timestamp.aurora.prewarm.json"
            Run-GatewayBenchmark -Name "Aurora" -Port $AuroraPort -OutPath $auroraOut -PrewarmOutPath $auroraPrewarmOut

            Stop-PprofCapture -Capture $auroraProfiles -Duration $Duration

            # Stop Aurora
            if ($proc -and -not $proc.HasExited) {
                Write-Host "Stopping Aurora..." -ForegroundColor DarkYellow
                Stop-Process -Id $proc.Id -Force
                $proc = $null
            }
        }
    }

    # ============================================================
    # 3. Write comparisons — all results are now collected
    # ============================================================
    Write-Host ""
    Write-Host ("=" * 70)
    Write-Host "  Comparison Reports"
    Write-Host ("=" * 70)

    $bifrostOut = Join-Path $resolvedResultsDir "$timestamp.bifrost.json"
    $auroraOut = Join-Path $resolvedResultsDir "$timestamp.aurora.json"
    $litellmOut = Join-Path $resolvedResultsDir "$timestamp.litellm.json"

    if ($StartBifrost -and $StartAurora -and (Test-Path $bifrostOut) -and (Test-Path $auroraOut)) {
        $comparisonBifrostOut = Join-Path $resolvedResultsDir "$timestamp.comparison-bifrost.json"
        Write-Comparison -BifrostPath $bifrostOut -AuroraPath $auroraOut -OutputPath $comparisonBifrostOut `
            -AuroraProfiles $auroraProfiles -BenchmarkRepo $BenchmarkRepo -ScenarioLabel "bifrost vs aurora (sequential)" `
            -Rate $Rate -Duration $Duration -Timeout $Timeout -WarmupRequests $WarmupRequests `
            -PrewarmRequests $PrewarmRequests -PrewarmConcurrency $PrewarmConcurrency `
            -Model $Model -Endpoint "/$Suffix/$Path" -BigPayload:$BigPayload `
            -BifrostPort $BifrostPort -AuroraPort $AuroraPort
        Write-ComparisonSummary -ComparisonPath $comparisonBifrostOut
        Write-Host "  Bifrost vs Aurora:   $comparisonBifrostOut" -ForegroundColor Green
    }

    if ($StartLiteLLM -and $StartAurora -and (Test-Path $litellmOut) -and (Test-Path $auroraOut)) {
        $comparisonLiteLLMOut = Join-Path $resolvedResultsDir "$timestamp.comparison-litellm.json"
        Write-Comparison -BifrostPath $litellmOut -AuroraPath $auroraOut -OutputPath $comparisonLiteLLMOut `
            -AuroraProfiles $auroraProfiles -BenchmarkRepo $BenchmarkRepo -ScenarioLabel "litellm vs aurora (sequential)" `
            -Rate $Rate -Duration $Duration -Timeout $Timeout -WarmupRequests $WarmupRequests `
            -PrewarmRequests $PrewarmRequests -PrewarmConcurrency $PrewarmConcurrency `
            -Model $Model -Endpoint "/$Suffix/$Path" -BigPayload:$BigPayload `
            -BifrostPort $LiteLLMPort -AuroraPort $AuroraPort

        # Three-way: Bifrost + LiteLLM + Aurora
        if ($StartBifrost -and (Test-Path $bifrostOut)) {
            $threeWayOut = Join-Path $resolvedResultsDir "$timestamp.comparison-threeway.json"
            Write-ThreeWayComparison -BifrostPath $bifrostOut `
                -LiteLLMPath $litellmOut -AuroraPath $auroraOut -OutputPath $threeWayOut `
                -AuroraProfiles $auroraProfiles -BenchmarkRepo $BenchmarkRepo `
                -Rate $Rate -Duration $Duration -Timeout $Timeout -WarmupRequests $WarmupRequests `
                -PrewarmRequests $PrewarmRequests -PrewarmConcurrency $PrewarmConcurrency `
                -Model $Model -Endpoint "/$Suffix/$Path" -BigPayload:$BigPayload `
                -BifrostPort $BifrostPort -LiteLLMPort $LiteLLMPort -AuroraPort $AuroraPort
            Write-ThreeWaySummary -ComparisonPath $threeWayOut
            Write-Host "  Three-way:           $threeWayOut" -ForegroundColor Green
        } else {
            Write-Host "  LiteLLM vs Aurora:   $comparisonLiteLLMOut" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "Benchmark complete." -ForegroundColor Green
}
finally {
    # Stop any remaining child processes
    if ($mockProc -and -not $mockProc.HasExited) {
        Write-Host "Stopping mock server..." -ForegroundColor DarkYellow
        Stop-Process -Id $mockProc.Id -Force
    }
}
