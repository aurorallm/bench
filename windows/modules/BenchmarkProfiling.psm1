$ErrorActionPreference = "Stop"

function Start-PprofCapture {
    param(
        [int]$Port,
        [string]$OutputPrefix,
        [int]$Seconds
    )

    $cpuPath = "$OutputPrefix.cpu.pprof"
    $heapPath = "$OutputPrefix.heap.pprof"
    $tracePath = "$OutputPrefix.trace.out"
    $goroutinePath = "$OutputPrefix.goroutine.pprof"

    $job = Start-Job -ScriptBlock {
        param($CpuUrl, $CpuPath, $HeapUrl, $HeapPath, $TraceUrl, $TracePath, $GoroutineUrl, $GoroutinePath)
        try {
            Invoke-WebRequest -Uri $CpuUrl -OutFile $CpuPath -UseBasicParsing | Out-Null
            Invoke-WebRequest -Uri $HeapUrl -OutFile $HeapPath -UseBasicParsing | Out-Null
            Invoke-WebRequest -Uri $TraceUrl -OutFile $TracePath -UseBasicParsing | Out-Null
            Invoke-WebRequest -Uri $GoroutineUrl -OutFile $GoroutinePath -UseBasicParsing | Out-Null
        } catch { }
    } -ArgumentList @(
        "http://127.0.0.1:$Port/debug/pprof/profile?seconds=$Seconds",
        $cpuPath,
        "http://127.0.0.1:$Port/debug/pprof/heap",
        $heapPath,
        "http://127.0.0.1:$Port/debug/pprof/trace?seconds=5",
        $tracePath,
        "http://127.0.0.1:$Port/debug/pprof/goroutine",
        $goroutinePath
    )

    return [ordered]@{
        job        = $job
        enabled    = $true
        cpu        = $cpuPath
        heap       = $heapPath
        trace      = $tracePath
        goroutine  = $goroutinePath
    }
}

function Stop-PprofCapture {
    param($Capture, [int]$Duration)

    if ($null -eq $Capture) { return }
    try {
        Wait-Job -Job $Capture.job -Timeout ($Duration + 30) | Out-Null
        Receive-Job -Job $Capture.job -ErrorAction Stop | Out-Null
        Write-Host "  pprof CPU:  $($Capture.cpu)" -ForegroundColor DarkGray
        Write-Host "  pprof heap: $($Capture.cpu)" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "pprof capture failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Job -Job $Capture.job -Force -ErrorAction SilentlyContinue
    }
}

function Get-PprofMetadata {
    param($Capture)
    if ($null -eq $Capture) {
        return [ordered]@{ enabled = $false }
    }
    return [ordered]@{
        enabled    = $true
        cpu        = $Capture.cpu
        heap       = $Capture.heap
        trace      = $Capture.trace
        goroutine  = $Capture.goroutine
    }
}

Export-ModuleMember -Function Start-PprofCapture, Stop-PprofCapture, Get-PprofMetadata
