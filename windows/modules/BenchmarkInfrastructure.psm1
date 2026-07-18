$ErrorActionPreference = "Stop"

function Build-MockServer {
    param([string]$BenchDir)

    $output = Join-Path $BenchDir "bin\mock-server.exe"
    $srcDir = Join-Path $BenchDir "mock-server"

    if (Test-Path $output) {
        $binTime = (Get-Item $output).LastWriteTime
        $newer = Get-ChildItem -Path $srcDir -Recurse -Include "*.go" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $binTime }
        if (-not $newer) {
            return $output
        }
        Write-Host "Mock server source changed, rebuilding..." -ForegroundColor Yellow
    }

    Write-Host "Building mock server..." -ForegroundColor Yellow
    Push-Location $srcDir
    try {
        go build -o $output ./main.go
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path $output)) {
        throw "Mock server build failed"
    }
    Write-Host "Mock server built: $output" -ForegroundColor Green
    return $output
}

function Start-MockServerProcess {
    param(
        [string]$ExePath,
        [int]$Port = 9099,
        [string]$Models = "",
        [switch]$NewWindow
    )

    $env:MOCK_PORT = [string]$Port
    $env:MOCKER_PORT = [string]$Port
    if ($Models -ne "") {
        $env:MOCK_MODELS = $Models
    }

    if ($NewWindow) {
        $cmd = "`$env:MOCK_PORT='$Port'; `$env:MOCKER_PORT='$Port';"
        if ($Models -ne "") { $cmd += " `$env:MOCK_MODELS='$Models';" }
        $cmd += " & '$ExePath'"
        return Start-Process powershell -ArgumentList "-NoExit", "-WindowStyle Normal", "-Command", $cmd -PassThru
    }

    return Start-Process -FilePath $ExePath -PassThru
}

function Invoke-Benchmark {
    param(
        [string]$Name,
        [int]$Port,
        [string]$OutputPath,
        [int]$Rate,
        [int]$Duration,
        [int]$Concurrency = 256,
        [string]$Model = "openai/gpt-4o-mini",
        [string]$Path = "v1/chat/completions",
        [string]$Auth = "sk-bench-test-key",
        [int]$Warmup = 25,
        [string]$CliPath,
        [hashtable]$Headers = @{},
        [string]$MockUrl = "",
        [string]$Phase = "Benchmark"
    )

    if (-not $CliPath -or -not (Test-Path $CliPath)) {
        throw "Benchmark CLI not found at $CliPath"
    }

    $args = @(
        "-port", [string]$Port,
        "-rate", [string]$Rate,
        "-duration", [string]$Duration,
        "-concurrency", [string]$Concurrency,
        "-model", $Model,
        "-path", $Path,
        "-auth", $Auth,
        "-warmup", [string]$Warmup,
        "-output", $OutputPath,
        "-quiet"
    )

    foreach ($kv in $Headers.GetEnumerator()) {
        $val = $kv.Value -replace '\$\{MOCK_URL\}', $MockUrl
        $args += "-header", "$($kv.Key):$val"
    }

    $phaseColor = if ($Phase -eq "Prewarm") { "DarkYellow" } else { "Cyan" }
    Write-Host "  [$Phase] ${Rate}req/s x ${Duration}s @ ${Concurrency} workers" -ForegroundColor $phaseColor

    $null = & $CliPath @args 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Benchmark CLI for $Name failed with exit code $LASTEXITCODE"
    }

    $result = Read-BenchmarkResult -Path $OutputPath

    $errCount = 0
    if ($result.error_breakdown) { $errCount = ($result.error_breakdown | ForEach-Object { $_.count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum }

    $color = if ($errCount -eq 0) { "Green" } elseif ($result.success_rate -ge 99) { "Yellow" } else { "Red" }

    if ($Phase -eq "Prewarm") {
        Write-Host ("  OK  {0,5} req  {1,6:F2}% | RPS {2,6:F1}/{3} | P50={4,6:F2} P90={5,6:F2} P95={6,6:F2} P99={7,6:F2} mean={8,6:F2} | Status {9}/{10}/{11}/{12}" -f
            $result.requests, $result.success_rate,
            $result.throughput_rps, $Rate,
            $result.p50_latency_ms, $result.p90_latency_ms, $result.p95_latency_ms, $result.p99_latency_ms, $result.mean_latency_ms,
            $result.status_200, $result.status_4xx, $result.status_5xx, $errCount) -ForegroundColor $color
        $script:lastPrewarmResult = $result
    } else {
        $pre = $script:lastPrewarmResult
        $rows = @(,("Throughput (req/s)", $result.throughput_rps, $(if ($pre) { $pre.throughput_rps } else { $null })))
        $rows += ,("Success rate (%)",   $result.success_rate,  $(if ($pre) { $pre.success_rate } else { $null }))
        $rows += ,("Mean latency (ms)",  $result.mean_latency_ms,$(if ($pre) { $pre.mean_latency_ms } else { $null }))
        $rows += ,("P50 latency (ms)",   $result.p50_latency_ms, $(if ($pre) { $pre.p50_latency_ms } else { $null }))
        $rows += ,("P90 latency (ms)",   $result.p90_latency_ms, $(if ($pre) { $pre.p90_latency_ms } else { $null }))
        $rows += ,("P95 latency (ms)",   $result.p95_latency_ms, $(if ($pre) { $pre.p95_latency_ms } else { $null }))
        $rows += ,("P99 latency (ms)",   $result.p99_latency_ms, $(if ($pre) { $pre.p99_latency_ms } else { $null }))
        $rows += ,("P999 latency (ms)",  $result.p999_latency_ms,$(if ($pre) { $pre.p999_latency_ms } else { $null }))
        $rows += ,("Max latency (ms)",   $result.max_latency_ms, $(if ($pre) { $pre.max_latency_ms } else { $null }))
        $rows += ,("Allocs/op",          $result.allocs_per_op,  $(if ($pre) { $pre.allocs_per_op } else { $null }))
        $rows += ,("Bytes/op",           $result.bytes_per_op,   $(if ($pre) { $pre.bytes_per_op } else { $null }))
        $rows += ,("Requests",           $result.requests,       $(if ($pre) { $pre.requests } else { $null }))

        $sepColor = if ($color -eq "Green" -or $color -eq "Yellow") { "Cyan" } else { $color }
        Write-Host "  $('-'*54)" -ForegroundColor $sepColor
        Write-Host ("  {0,-28}  {1,12}  {2,12}" -f "Metric", "Benchmark", "Prewarm") -ForegroundColor $color
        Write-Host "  $('-'*54)" -ForegroundColor $sepColor
        foreach ($r in $rows) {
            $lbl = $r[0]
            $cv = $r[1]
            $pv = $r[2]
            $cf = if ($null -ne $cv) { "{0,12:n2}" -f [double]$cv } else { "".PadLeft(12) }
            $pf = if ($null -ne $pv) { "{0,12:n2}" -f [double]$pv } else { "".PadLeft(12) }
            Write-Host ("  {0,-28}  {1,12}  {2,12}" -f $lbl, $cf, $pf) -ForegroundColor $color
        }
        Write-Host "  $('-'*54)" -ForegroundColor $sepColor
        $ecPre = 0
        if ($pre -and $pre.error_breakdown) { $ecPre = ($pre.error_breakdown | ForEach-Object { $_.count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum }
        $preStatus = if ($pre) { "$($pre.status_200)/$($pre.status_4xx)/$($pre.status_5xx)/$ecPre" } else { "" }
        Write-Host ("  {0,-28}  {1,12}  {2,12}" -f "Status codes", "$($result.status_200)/$($result.status_4xx)/$($result.status_5xx)/$errCount", $preStatus) -ForegroundColor $color
        if ($errCount -gt 0 -and $result.error_breakdown) {
            foreach ($e in $result.error_breakdown) {
                if ($e.count -gt 0 -and $e.message) {
                    Write-Host ("  {0,-28}     [{1,3}x] {2}" -f "", $e.count, $e.message) -ForegroundColor "DarkYellow"
                }
            }
        }
    }
}

function Clear-BenchBinaries {
    param([string]$BenchDir)

    $binDir = Join-Path $BenchDir "bin"
    if (Test-Path $binDir) {
        $exes = Get-ChildItem -Path $binDir -Filter "*.exe" -ErrorAction SilentlyContinue
        if ($exes) {
            $exes | Remove-Item -Force
            Write-Host "  Cleaned $($exes.Count) old binary(s)" -ForegroundColor DarkYellow
        }
    }
}

function Build-AllBinaries {
    param([string]$BenchDir)

    $binDir = Join-Path $BenchDir "bin"
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null

    # 1. Mock server
    $mockOut = Join-Path $binDir "mock-server.exe"
    Write-Host "  Building mock server..." -ForegroundColor Cyan
    Push-Location (Join-Path $BenchDir "mock-server")
    try { go build -o $mockOut ./main.go } finally { Pop-Location }
    if (-not (Test-Path $mockOut)) { throw "Mock server build failed" }

    # 2. Benchmark CLI
    $cliOut = Join-Path $binDir "aurora-bench-cli.exe"
    $cliSrc = Join-Path $BenchDir "tools\benchmark-cli"
    Write-Host "  Building benchmark CLI..." -ForegroundColor Cyan
    Push-Location $BenchDir
    try { go build -o $cliOut $cliSrc } finally { Pop-Location }
    if (-not (Test-Path $cliOut)) { throw "Benchmark CLI build failed" }

    # 3. Aurora gateway - pre-built
    $auroraOut = Join-Path $binDir "aurora-bench.exe"
    if (Test-Path $auroraOut) {
        Write-Host "  Using pre-built Aurora: $auroraOut" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: No pre-built Aurora binary found. Place one at $auroraOut" -ForegroundColor Yellow
    }

    Write-Host "  All binaries built fresh." -ForegroundColor Green
    return @{
        MockServer = $mockOut
        BenchCli   = $cliOut
        Aurora     = if (Test-Path $auroraOut) { $auroraOut } else { $null }
    }
}

function Verify-MockServerModel {
    param(
        [int]$Port = 9099,
        [string]$ExpectedModel = "gpt-4o-mini",
        [string]$EndpointPath = "v1/chat/completions",
        [string]$TestMessage = "verify model",
        [int]$TimeoutSeconds = 10
    )

    $url = "http://127.0.0.1:$Port/$EndpointPath"
    $body = @{
        model    = $ExpectedModel
        messages = @(@{ role = "user"; content = $TestMessage })
        stream   = $false
    } | ConvertTo-Json -Depth 4 -Compress

    Write-Host "  Verifying mock server model at $url..." -ForegroundColor DarkGray

    try {
        $r = Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Body $body -UseBasicParsing -TimeoutSec $TimeoutSeconds
        if ($r.StatusCode -ne 200) {
            throw "Mock server returned HTTP $($r.StatusCode)"
        }

        $resp = $r.Content | ConvertFrom-Json
        $responseModel = $resp.model
        $responseContent = $resp.choices[0].message.content

        if ($responseModel -ne $ExpectedModel) {
            throw "Model MISMATCH: sent '$ExpectedModel', got '$responseModel'"
        }

        Write-Host "  Mock server model OK: '$responseModel'" -ForegroundColor Green
        Write-Host "     Response snippet: '$($responseContent.Substring(0, [Math]::Min(60, $responseContent.Length)))...'" -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Host "  Mock server verification FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function Build-MockServer, Start-MockServerProcess, Invoke-Benchmark, `
    Clear-BenchBinaries, Build-AllBinaries, Verify-MockServerModel
