$ErrorActionPreference = "Stop"

function Read-BenchmarkResult {
    param([string]$Path, [string]$ProviderName = "aurora")

    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    if ($json.requests -ne $null) {
        return $json
    }
    if ($null -ne $json.$ProviderName) {
        return $json.$ProviderName
    }
    return $json
}

function Write-GenericComparison {
    param(
        [hashtable]$Results,         # @{ "gatewayName" = @{ path = "..."; data = {...} } }
        [string]$OutputPath,
        [hashtable]$Config,          # rate, duration, etc.
        [bool]$BigPayload
    )

    $names = @($Results.Keys)
    $baseName = $names[0]
    $baseline = $Results[$baseName].data

    $gates = [ordered]@{}
    foreach ($name in $names) {
        $gates[$name] = $Results[$name].data
    }

    $deltas = [ordered]@{}
    foreach ($name in $names) {
        if ($name -eq $baseName) { continue }
        $other = $Results[$name].data
        $deltas["${name}_vs_${baseName}"] = [ordered]@{
            throughput_rps      = [math]::Round($other.throughput_rps - $baseline.throughput_rps, 2)
            mean_latency_ms     = [math]::Round($other.mean_latency_ms - $baseline.mean_latency_ms, 4)
            p50_latency_ms      = [math]::Round($other.p50_latency_ms - $baseline.p50_latency_ms, 4)
            p90_latency_ms      = [math]::Round($other.p90_latency_ms - $baseline.p90_latency_ms, 4)
            p95_latency_ms      = [math]::Round($other.p95_latency_ms - $baseline.p95_latency_ms, 4)
            p99_latency_ms      = [math]::Round($other.p99_latency_ms - $baseline.p99_latency_ms, 4)
            p999_latency_ms     = [math]::Round($other.p999_latency_ms - $baseline.p999_latency_ms, 4)
            max_latency_ms      = if ($null -ne $other.max_latency_ms -and $null -ne $baseline.max_latency_ms) { [math]::Round($other.max_latency_ms - $baseline.max_latency_ms, 4) } else { $null }
            success_rate        = if ($null -ne $other.success_rate -and $null -ne $baseline.success_rate) { [math]::Round($other.success_rate - $baseline.success_rate, 4) } else { $null }
            allocs_per_op       = if ($null -ne $other.allocs_per_op -and $null -ne $baseline.allocs_per_op) { [math]::Round($other.allocs_per_op - $baseline.allocs_per_op, 2) } else { $null }
            bytes_per_op        = if ($null -ne $other.bytes_per_op -and $null -ne $baseline.bytes_per_op) { [math]::Round($other.bytes_per_op - $baseline.bytes_per_op, 2) } else { $null }
        }
    }

    $comparison = [ordered]@{
        metadata = [ordered]@{
            generated_at    = (Get-Date).ToString("o")
            gateways        = $names
            baseline        = $baseName
            tool            = "aurora-bench-cli (QPC-timed)"
            machine = [ordered]@{
                hostname            = $env:COMPUTERNAME
                os                  = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
                arch                = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
                logical_processors  = [Environment]::ProcessorCount
            }
            config = [ordered]@{
                rate              = $Config.Rate
                duration_seconds  = $Config.Duration
                model             = $Config.Model
                endpoint          = $Config.Endpoint
                big_payload       = $BigPayload
            }
        }
        results = $gates
        deltas  = $deltas
    }

    $comparison | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $OutputPath -Encoding ASCII
    Write-Host "Comparison written to: $OutputPath" -ForegroundColor Cyan
}

function Write-ComparisonSummary {
    param([string]$ComparisonPath)

    $data = Get-Content -LiteralPath $ComparisonPath -Raw | ConvertFrom-Json
    $names = @($data.metadata.gateways)

    $colWidth = [Math]::Max(18, [Math]::Floor(60 / $names.Count))
    $tableWidth = 34 + $colWidth * $names.Count
    $line = ('=' * $tableWidth)
    $header = "Benchmark Comparison"
    Write-Host ""
    Write-Host "  $line"
    Write-Host "  |$(' ' * ([Math]::Max(0, ($line.Length - $header.Length - 4) / 2))) $header $(' ' * ([Math]::Max(0, ($line.Length - $header.Length - 4 + 1) / 2))) |"
    Write-Host "  $line"
    Write-Host ""
    Write-Host "  Config: $($data.metadata.config.rate) req/s x $($data.metadata.config.duration_seconds)s"
    Write-Host "  Model: $($data.metadata.config.model) | Endpoint: $($data.metadata.config.endpoint)"
    Write-Host "  Host: $($data.metadata.machine.hostname) ($($data.metadata.machine.logical_processors) CPUs)"
    Write-Host ""

    function field($obj, $name, $default = "N/A") {
        if ($null -eq $obj -or $null -eq $obj.$name) { return $default }
        return $obj.$name
    }

    $nameHeader = ("{0,-34}" -f "Metric")
    foreach ($n in $names) {
        $nameHeader += ("{0,$colWidth}" -f $n)
    }
    Write-Host "  $nameHeader" -ForegroundColor DarkGray
    Write-Host ("  {0}" -f ('-' * (34 + $colWidth * $names.Count))) -ForegroundColor DarkGray

    $metrics = @(
        @{ key = "throughput_rps"; label = "Throughput (req/s)"; fmt = "n2" }
        @{ key = "mean_latency_ms"; label = "Mean latency (ms)"; fmt = "n3" }
        @{ key = "p50_latency_ms"; label = "P50 latency (ms)"; fmt = "n3" }
        @{ key = "p90_latency_ms"; label = "P90 latency (ms)"; fmt = "n3" }
        @{ key = "p95_latency_ms"; label = "P95 latency (ms)"; fmt = "n3" }
        @{ key = "p99_latency_ms"; label = "P99 latency (ms)"; fmt = "n3" }
        @{ key = "p999_latency_ms"; label = "P999 latency (ms)"; fmt = "n3" }
        @{ key = "max_latency_ms"; label = "Max latency (ms)"; fmt = "n3" }
        @{ key = "success_rate"; label = "Success %"; fmt = "n2" }
        @{ key = "allocs_per_op"; label = "Allocs/op"; fmt = "n1" }
        @{ key = "bytes_per_op"; label = "Bytes/op"; fmt = "n0" }
        @{ key = "requests"; label = "Requests"; fmt = "n0" }
    )

    foreach ($m in $metrics) {
        $vals = @()
        foreach ($n in $names) {
            $v = field $data.results.$n $m.key 0
            if ($m.fmt) { $vals += "{0,$($colWidth):$($m.fmt)}" -f [double]$v }
            else { $vals += "{0,$colWidth}" -f $v }
        }
        Write-Host ("  {0,-34}" -f $m.label) -NoNewline
        foreach ($v in $vals) { Write-Host " $v" -NoNewline }
        Write-Host ""
    }

    Write-Host ""
    Write-Host ("  {0,-34}" -f "Status codes (200/4xx/5xx/err)") -NoNewline
    foreach ($n in $names) {
        $d = $data.results.$n
        $errCount = 0
        if ($d.error_breakdown) { $errCount = ($d.error_breakdown | ForEach-Object { $_.count }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum }
        Write-Host (" {0,$colWidth}" -f "$(field $d "status_200" 0)/$(field $d "status_4xx" 0)/$(field $d "status_5xx" 0)/$errCount") -NoNewline
    }
    Write-Host ""
    # Show error breakdown when errors exist
    foreach ($n in $names) {
        $d = $data.results.$n
        $eb = $d.error_breakdown
        if ($eb) {
            foreach ($e in $eb) {
                if ($e.count -gt 0 -and $e.message) {
                    $msg = $e.message
                    Write-Host ("  {0,-34}  [{1,3}x] {2}" -f "  $n errors", $e.count, $msg) -ForegroundColor DarkYellow
                }
            }
        }
    }
    Write-Host ""

    # Delta section
    if ($data.deltas) {
        Write-Host "  Deltas (vs $($data.metadata.baseline)):" -ForegroundColor DarkGray
        Write-Host ("  {0}" -f ('-' * (34 + $colWidth * ($names.Count - 1)))) -ForegroundColor DarkGray
        $deltaMetrics = @("throughput_rps", "mean_latency_ms", "p50_latency_ms", "p90_latency_ms", "p95_latency_ms", "p99_latency_ms", "p999_latency_ms", "max_latency_ms", "success_rate", "allocs_per_op", "bytes_per_op")
        foreach ($m in $deltaMetrics) {
            $label = ($m -replace '_latency_ms', ' (ms)' -replace '_per_op', '/op' -replace '_rps', ' (rps)' -replace '_', ' ')
            Write-Host ("  {0,-34}" -f "  $label") -NoNewline
            foreach ($dk in @($data.deltas.PSObject.Properties.Name)) {
                $raw = $data.deltas.$dk.$m
                if ($null -eq $raw) {
                    $display = "N/A".PadLeft($colWidth)
                } else {
                    $display = "{0,$($colWidth):n3}" -f $raw
                }
                Write-Host " $display" -NoNewline
            }
            Write-Host ""
        }
        Write-Host ""
    }

    Write-Host "  $line"
    Write-Host ""
}

Export-ModuleMember -Function Read-BenchmarkResult, Write-GenericComparison, Write-ComparisonSummary
