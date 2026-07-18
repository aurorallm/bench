param(
    [string[]]$Competitors = @("aurora"),
    [int]$Rate = 0,
    [int]$Duration = 0,
    [string]$Mode = "auto",
    [int]$MockPort = 9099,
    [string]$ApiKey = "sk-bench-test-key",
    [string]$Model = "gpt-4o-mini",
    [int]$WarmupRequests = 25,
    [int]$PrewarmRequests = 256,
    [int]$PrewarmConcurrency = 64,
    [int]$Concurrency = 256,
    [switch]$List,
    [switch]$NoWindow,
    [switch]$Help,
    [switch]$Clean,
    [switch]$SkipModelVerify
)

if ($Help) {
    function color { param($c,$t) Write-Host $t -ForegroundColor $c }
    function header { param($t) color Cyan "`n$t"; color DarkGray ('=' * $t.Length) }
    function flag { param($f,$d) color DarkYellow ("  {0,-30} " -f $f); color Gray $d }

    color Cyan  "`n  Aurora Benchmark Framework [Windows]"
    color Gray  "  Compare AI gateways with reproducible results."
    color White "  Docs: .\README.md | linux/run.sh or mac/run.sh for other platforms"

    header "USAGE"
    color Yellow "  .\windows\run.ps1 [-Competitors aurora,bifrost,...] [-Mode smoke|sweat|endurance|publish|brutal|auto] [options]"

    header "HOW IT WORKS"
    color Gray  "  1. Builds mock server + bench CLI binaries (use -Clean to rebuild)"
    color Gray  "  2. Starts Mock Server (Go HTTP server mimicking OpenAI API, port 9099)"
    color Gray  "  3. Verifies model echo"
    color Gray  "  4. Starts each gateway sequentially (one at a time, full machine resources)"
    color Gray  "  5. Runs benchmark CLI (QPC-precision timers) at target rate x duration"
    color Gray  "  6. Produces comparison JSON with latency percentiles, throughput, deltas"

    header "BENCHMARK OPTIONS"
    flag "-Competitors [list]" "Comma-separated: aurora, bifrost, litellm, portkey, helicone (default: aurora)"
    flag "-Mode [mode]"        "smoke (100x20s), sweat (500x30s), endurance (6000x60s), publish (10000x60s), brutal (15000x60s), auto (4000x120s)"
    flag "-Rate [n]"           "Target requests per second (default: auto from mode)"
    flag "-Duration [n]"       "Benchmark duration in seconds (default: auto from mode)"
    flag "-Concurrency [n]"    "Concurrent HTTP workers (default: 256)"
    flag "-Model [name]"       "Model name in request payload (default: gpt-4o-mini)"
    flag "-MockPort [n]"       "Mock server port (default: 9099)"
    flag "-ApiKey [key]"       "Auth token for all gateways (default: sk-bench-test-key)"
    flag "-WarmupRequests [n]" "Serial warmup requests before measured run (default: 25)"
    flag "-PrewarmRequests [n]" "Burst prewarm at full rate before measured run (default: 256)"
    flag "-PrewarmConcurrency"  "Concurrency for prewarm burst (default: 64)"

    header "PLATFORM"
    flag "-Clean"          "Delete old binaries and rebuild mock-server & bench-cli"
    color Gray  "  Binaries: .\bin\windows\*.exe"
    color Gray  "  Cross-platform: linux/run.sh, mac/run.sh"

    header "OUTPUT"
    color Gray  "  Results: bench-results/{gateway1-vs-gateway2}/"

    header "EXAMPLES"
    color Yellow "  .\windows\run.ps1 -List"
    color Yellow "`n  .\windows\run.ps1 -Clean -Competitors aurora"
    color Yellow "`n  .\windows\run.ps1 -Competitors aurora,bifrost,litellm -Mode smoke"
    return
}

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path $scriptDir -Parent
$modulesPath = Join-Path $scriptDir "modules"

Import-Module (Join-Path $modulesPath "BenchmarkUtilities.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkInfrastructure.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkComparison.psm1") -Force
Import-Module (Join-Path $modulesPath "BenchmarkProfiling.psm1") -Force

$loadedCompetitors = @{}
Get-ChildItem (Join-Path $scriptDir "competitors\*.ps1") | Where-Object { $_.Name -notlike '_*' } | ForEach-Object {
    $info = & $_.FullName
    if ($info -and $info.Name) {
        $loadedCompetitors[$info.Name] = $info
    }
}

if ($List) {
    Write-Host ""
    Write-Host "Available competitors (Windows):" -ForegroundColor Cyan
    $loadedCompetitors.Keys | Sort-Object | ForEach-Object {
        $c = $loadedCompetitors[$_]
        Write-Host "  $_".PadRight(20) -NoNewline
        Write-Host "$($c.DisplayName)" -ForegroundColor White
        Write-Host "    Type: $($c.Type)".PadRight(20) -NoNewline
        Write-Host "Language: $($c.Language)".PadRight(20) -NoNewline
        Write-Host "Port: $($c.DefaultPort)"
        Write-Host ""
    }
    return
}

$selected = @()
foreach ($name in $Competitors) {
    if (-not $loadedCompetitors.ContainsKey($name)) {
        Write-Host "ERROR: Unknown competitor '$name'. Use -List to see available." -ForegroundColor Red
        exit 1
    }
    $selected += $loadedCompetitors[$name]
}

Write-Host ""
Write-Host ("=" * 70)
Write-Host "  Aurora Benchmark Runner [Windows]"
Write-Host ("=" * 70)
Write-Host "  Platform:  $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
Write-Host "  Gateways:  $($selected.Count)"
$selected | ForEach-Object { Write-Host "    - $($_.DisplayName) ($($_.Name)): port $($_.DefaultPort)" }

$allPorts = @($MockPort) + ($selected | ForEach-Object { $_.DefaultPort })
Write-Host "  Cleaning ports: $($allPorts -join ', ')" -ForegroundColor DarkYellow
Stop-BenchProcesses -Ports $allPorts
Start-Sleep -Seconds 1

if ($Mode -eq "auto") {
    if ($Rate -eq 0 -and $Duration -eq 0) {
        $Rate = 4000
        $Duration = 120
    }
} elseif ($Mode -eq "smoke") {
    $Rate = 100
    $Duration = 20
} elseif ($Mode -eq "sweat") {
    $Rate = 500
    $Duration = 30
} elseif ($Mode -eq "endurance") {
    $Rate = 6000
    $Duration = 60
} elseif ($Mode -eq "publish") {
    $Rate = 10000
    $Duration = 60
} elseif ($Mode -eq "brutal") {
    $Rate = 15000
    $Duration = 60
}

if ($Rate -le 0) { $Rate = 1000 }
if ($Duration -le 0) { $Duration = 30 }

Write-Host "  Rate:      $Rate req/s"
Write-Host "  Duration:  ${Duration}s"
Write-Host "  Mock port: $MockPort"
Write-Host "  Model:     $Model"
Write-Host "  Clean build: $Clean"
Write-Host "  Verify model: $(-not $SkipModelVerify)"
Write-Host ("=" * 70)
Write-Host ""

if ($Clean) {
    Write-Host "Cleaning old binaries and rebuilding fresh..." -ForegroundColor Yellow
    Clear-BenchBinaries -BenchDir $repoRoot
    $built = Build-AllBinaries -BenchDir $repoRoot -RepoRoot $repoRoot
    $mockExe = $built.MockServer
    $cliPath = $built.BenchCli
} else {
    $mockExe = Build-MockServer -BenchDir $repoRoot
    $cliPath = Build-BenchCli -BenchDir $repoRoot
}

$resultsDir = Join-Path $repoRoot "bench-results"
$scenarioLabel = ($selected.Name -join "-vs-")
$runDir = Join-Path $resultsDir $scenarioLabel
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

Write-Host "Starting mock server on port $MockPort..." -ForegroundColor Cyan
$mockProc = Start-MockServerProcess -ExePath $mockExe -Port $MockPort -Models $Model -NewWindow:$NoWindow
Wait-ForHealth -Name "Mock Server" -Port $MockPort -TimeoutSeconds 15 -HealthPath "health"

if (-not $SkipModelVerify) {
    Write-Host ""
    Write-Host "Verifying mock server model..." -ForegroundColor Cyan
    $verified = Verify-MockServerModel -Port $MockPort -ExpectedModel $Model
    if (-not $verified) {
        throw "Mock server model verification failed. Expected model '$Model'."
    }
    Write-Host ""
}

try {
    & (Join-Path $scriptDir "scenarios\compare.ps1") `
        -Competitors $selected `
        -BenchDir $repoRoot `
        -RepoRoot $repoRoot `
        -ResultsDir $runDir `
        -MockUrl "http://127.0.0.1:$MockPort" `
        -ApiKey $ApiKey `
        -Rate $Rate `
        -Duration $Duration `
        -WarmupRequests $WarmupRequests `
        -PrewarmRequests $PrewarmRequests `
        -PrewarmConcurrency $PrewarmConcurrency `
        -Model $Model `
        -EndpointSuffix "v1" `
        -EndpointPath "chat/completions" `
        -CliPath $cliPath `
        -Concurrency $Concurrency `
        -NewWindow:$(-not $NoWindow)
}
finally {
    Write-Host "  Cleaning up benchmark processes..." -ForegroundColor DarkYellow
    Stop-BenchProcesses -Ports $allPorts
    Start-Sleep -Milliseconds 500
}
