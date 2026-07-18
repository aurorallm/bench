param(
    [string]$BenchmarkRepo = "",
    [string]$BenchmarkUrl = "https://github.com/maximhq/bifrost-benchmarking.git",
    [string]$ResultsDir = "bench-results\aurora-standalone",
    [int]$Port = 8081,
    [int]$MockPort = 9099,
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
    [switch]$NewWindow,
    [switch]$StartMock,
    [string]$MockExePath = "",
    [string]$AuroraUpstreamBaseUrl = "",
    [string]$AuroraUpstreamApiKey = "sk-bench-test-key"
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $PSCommandPath
$benchDir = Split-Path -Parent $scriptPath
$modulesPath = Join-Path $benchDir "modules"

Import-Module (Join-Path $modulesPath "BenchmarkUtilities.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkInfrastructure.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkProfiling.psm1") -Force

# Resolve temp workspace for benchmark repo
if ([string]::IsNullOrEmpty($BenchmarkRepo)) {
    $tempBase = if ($env:OPENCODE_TEMP) { $env:OPENCODE_TEMP } else { Join-Path $env:TEMP "opencode" }
    $BenchmarkRepo = Join-Path $tempBase "bifrost-benchmarking"
}

$repoRoot = $benchDir
$resolvedResultsDir = Join-Path $repoRoot $ResultsDir
New-Item -ItemType Directory -Force -Path $resolvedResultsDir | Out-Null

Ensure-BenchmarkRepo -BenchmarkRepo $BenchmarkRepo -BenchmarkUrl $BenchmarkUrl
$benchmarkExe = Ensure-BenchmarkBinary -BenchmarkRepo $BenchmarkRepo
Ensure-BenchmarkEnv -BenchmarkRepo $BenchmarkRepo -BifrostPort $Port -ApiKey $AuroraUpstreamApiKey

$auroraExe = Join-Path $benchDir "bin\aurora-bench.exe"

$procs = @()
try {
    if ($StartMock) {
        $mockBinary = if ($MockExePath -ne "" -and (Test-Path $MockExePath)) {
            $MockExePath
        } else {
            $mockBinaryDefault = Join-Path $benchDir "bin\mock-server.exe"
            if (-not (Test-Path $mockBinaryDefault)) {
                Write-Host "Building mock server..." -ForegroundColor Yellow
                Push-Location (Join-Path $benchDir "mock-server")
                try { go build -o $mockBinaryDefault ./main.go } finally { Pop-Location }
            }
            $mockBinaryDefault
        }
        Write-Host "Starting mock server on port $MockPort..." -ForegroundColor Cyan
        if ($NewWindow) {
            $proc = Start-MockServer -ExePath $mockBinary -Port $MockPort -Title "Mock Server ($MockPort)" -NewWindow
        } else {
            $proc = Start-MockServer -ExePath $mockBinary -Port $MockPort
        }
        $procs += $proc
        Wait-ForHealth -Name "Mock Server" -Port $MockPort -TimeoutSeconds 15 -HealthPath "health"
    }

    if ($AuroraUpstreamBaseUrl -eq "") {
        throw "-StartAurora requires -AuroraUpstreamBaseUrl"
    }

    if (-not (Test-Path $auroraExe)) {
        Write-Host "WARNING: Aurora binary not found at $auroraExe. Build it from the aurora repo." -ForegroundColor Yellow
        throw "Aurora binary not found. Build from aurora source: go build -o $auroraExe ./apps/aurora"
    }

    Write-Host "Starting Aurora on port $Port..." -ForegroundColor Cyan
    $auroraLog = Join-Path $resolvedResultsDir "aurora-server.log"
    if ($NewWindow) {
        $proc = Start-AuroraBenchServer -ExePath $auroraExe -Port $Port `
            -UpstreamBaseUrl $AuroraUpstreamBaseUrl -UpstreamApiKey $AuroraUpstreamApiKey -LogPath $auroraLog -NewWindow
    } else {
        $proc = Start-AuroraBenchServer -ExePath $auroraExe -Port $Port `
            -UpstreamBaseUrl $AuroraUpstreamBaseUrl -UpstreamApiKey $AuroraUpstreamApiKey -LogPath $auroraLog
    }
    $procs += $proc
    Wait-ForHealth -Name "Aurora" -Port $Port -TimeoutSeconds 30

    Start-Sleep -Seconds 2

    # Preflight check
    Invoke-Preflight -Name "Aurora" -Port $Port -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey

    # Warmup
    Invoke-Warmup -Name "Aurora" -Port $Port -WarmupRequests $WarmupRequests -Model $Model -Suffix $Suffix -Path $Path -AuthToken $AuroraUpstreamApiKey

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $auroraOut = Join-Path $resolvedResultsDir "$timestamp.aurora.json"
    $auroraPrewarmOut = Join-Path $resolvedResultsDir "$timestamp.aurora.prewarm.json"

    $winFlag = if ($NewWindow) { " +windows" } else { "" }
    Write-Host "Scenario (standalone): rate=$Rate duration=${Duration}s model=$Model path=/$Suffix/$Path warmup=$WarmupRequests prewarm=$PrewarmRequests/$PrewarmConcurrency${winFlag}"

    # Prewarm
    if ($PrewarmRequests -gt 0) {
        Invoke-AuroraBench -Name "Aurora (prewarm)" -Port $Port -OutputPath $auroraPrewarmOut `
            -Rate $Rate -Duration 10 -Concurrency $PrewarmConcurrency -Model $Model -Path "${Suffix}/${Path}" `
            -Auth $AuroraUpstreamApiKey -Warmup 0 -BenchDir $benchDir
    }

    # Main benchmark (QPC-precision timers)
    Invoke-AuroraBench -Name "Aurora" -Port $Port -OutputPath $auroraOut `
        -Rate $Rate -Duration $Duration -Concurrency 256 -Model $Model -Path "${Suffix}/${Path}" `
        -Auth $AuroraUpstreamApiKey -Warmup $WarmupRequests -BenchDir $benchDir

    Write-Host "Aurora results: $auroraOut" -ForegroundColor Green
}
finally {
    foreach ($proc in $procs) {
        Stop-AuroraProcess -Process $proc
    }
}
