param(
    [array]$Competitors,            # Array of competitor hashtables
    [string]$BenchDir,
    [string]$RepoRoot,
    [string]$ResultsDir,
    [string]$MockUrl,
    [string]$ApiKey = "sk-bench-test-key",
    [int]$Rate,
    [int]$Duration,
    [int]$WarmupRequests = 25,
    [int]$PrewarmRequests = 0,
    [int]$PrewarmConcurrency = 64,
    [string]$Model = "openai/gpt-4o-mini",
    [string]$EndpointSuffix = "v1",
    [string]$EndpointPath = "chat/completions",
    [string]$CliPath,
    [int]$Concurrency = 256,
    [switch]$NewWindow
)

$ErrorActionPreference = "Stop"
$results = @{}    # name → { path, data }

$procs = @()      # All running processes for cleanup

try {
    foreach ($c in $Competitors) {
        $name = $c.Name
        $port = $c.DefaultPort

        # Per-competitor path override if defined
        $compSuffix = if ($c.EndpointSuffix) { $c.EndpointSuffix } else { $EndpointSuffix }
        $compPath = if ($c.EndpointPath) { $c.EndpointPath } else { $EndpointPath }
        $benchPath = if ($c.BenchmarkPath) { $c.BenchmarkPath } else { "${compSuffix}/${compPath}" }
        Write-Host ""
        Write-Host ("=" * 70)
        Write-Host "  Gateway: $($c.DisplayName) ($name) on port $port" -ForegroundColor Cyan
        Write-Host ("=" * 70)

        # Clean port before starting
        Stop-ProcessOnPort -Ports @($port)
        Start-Sleep -Seconds 1

        # 1. Install / find binary
        $exePath = & $c.Install $BenchDir $RepoRoot

        # 2. Start gateway
        Write-Host "  Starting $($c.DisplayName)..." -ForegroundColor Cyan
        $proc = & $c.Start -ExePath $exePath -Port $port -MockUrl $MockUrl -ApiKey $ApiKey -ResultsDir $ResultsDir -NewWindow:$NewWindow
        $procs += $proc

        # 3. Wait for health
        $healthHeaders = if ($c.HealthCheckHeaders) { $c.HealthCheckHeaders } elseif ($c.Headers) { $c.Headers } else { @{} }
        $resolvedHealthHeaders = @{}
        foreach ($kv in $healthHeaders.GetEnumerator()) {
            $resolvedHealthHeaders[$kv.Key] = $kv.Value -replace '\$\{MOCK_URL\}', $MockUrl
        }
        $healthCheckType = if ($c.HealthCheckType) { $c.HealthCheckType } else { "http" }
        Wait-ForHealth -Name $c.DisplayName -Port $port -TimeoutSeconds $c.HealthTimeoutSeconds -HealthPath $c.HealthPath -Headers $resolvedHealthHeaders -CheckType $healthCheckType

        # 4. Preflight
        $headers = if ($c.Headers) { $c.Headers } else { @{} }
        $resolvedHeaders = @{}
        foreach ($kv in $headers.GetEnumerator()) {
            $resolvedHeaders[$kv.Key] = $kv.Value -replace '\$\{MOCK_URL\}', $MockUrl
        }
        Invoke-Preflight -Name $c.DisplayName -Port $port -Model $c.PreflightModel -Suffix $c.PreflightSuffix -Path $c.PreflightPath -AuthToken $ApiKey -ExtraHeaders $resolvedHeaders

        # 5. Prewarm burst (warms up gateway concurrency)
        $benchModel = if ($c.BenchmarkModel) { $c.BenchmarkModel } else { $Model }
        if ($PrewarmRequests -gt 0) {
            $prewarmOut = Join-Path $ResultsDir "$name.prewarm.json"
            Invoke-Benchmark -Name $c.DisplayName -Port $port -OutputPath $prewarmOut `
                -Rate $Rate -Duration 10 -Concurrency $PrewarmConcurrency -Model $benchModel -Path $benchPath `
                -Auth $ApiKey -Warmup $WarmupRequests -CliPath $CliPath -Headers $resolvedHeaders -MockUrl $MockUrl -Phase "Prewarm"
        }

        # 6. Main benchmark
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $outPath = Join-Path $ResultsDir "$timestamp.$name.json"
        Invoke-Benchmark -Name $c.DisplayName -Port $port -OutputPath $outPath `
            -Rate $Rate -Duration $Duration -Concurrency $Concurrency -Model $benchModel -Path $benchPath `
            -Auth $ApiKey -Warmup 0 -CliPath $CliPath -Headers $resolvedHeaders -MockUrl $MockUrl -Phase "Benchmark"

        $results[$name] = @{ path = $outPath }

        # 7. Stop gateway + cooldown
        Write-Host "  Stopping $($c.DisplayName)..." -ForegroundColor DarkYellow
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
            $proc = $null
        }
        if ($competitors.IndexOf($c) -lt $Competitors.Count - 1) {
            Write-Host "  Cooldown 5s..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
        }
    }

    # ============================================================
    # 3. Read results and generate comparison
    # ============================================================
    foreach ($name in $results.Keys) {
        $results[$name].data = Read-BenchmarkResult -Path $results[$name].path
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $comparisonOut = Join-Path $ResultsDir "$timestamp.comparison.json"

    $config = @{
        Rate     = $Rate
        Duration = $Duration
        Model    = $Model
        Endpoint = "/$EndpointSuffix/$EndpointPath"
    }

    Write-GenericComparison -Results $results -OutputPath $comparisonOut -Config $config
    Write-ComparisonSummary -ComparisonPath $comparisonOut

    Write-Host ""
    Write-Host "All benchmarks complete." -ForegroundColor Green
    Write-Host "Results: $ResultsDir" -ForegroundColor Green
}
finally {
    foreach ($proc in $procs) {
        if ($null -ne $proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    # Clean competitor ports (don't kill Docker/mock-server - managed by run.ps1)
    @($Competitors | ForEach-Object { $_.DefaultPort }) | ForEach-Object {
        $port = $_
        try {
            $connections = netstat -ano | Select-String "LISTENING" | Select-String ":$port "
            foreach ($conn in $connections) {
                $parts = $conn -split '\s+'
                $pid = $parts[-1]
                if (-not $pid -or $pid -notmatch '^\d+$') { continue }
                $skip = $false
                try { $p = Get-Process -Id $pid; if ($p.ProcessName -match 'docker|wsl|com\.docker') { $skip = $true } } catch {}
                if (-not $skip) { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue }
            }
        } catch {}
    }
}
