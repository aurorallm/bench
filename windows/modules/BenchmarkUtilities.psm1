$ErrorActionPreference = "Stop"

function Wait-ForHealth {
    param(
        [string]$Name,
        [int]$Port,
        [int]$TimeoutSeconds = 30,
        [string]$HealthPath = "health",
        [hashtable]$Headers = @{},
        [string]$CheckType = "http"
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    if ($CheckType -eq "tcp") {
        do {
            try {
                $sock = New-Object System.Net.Sockets.TcpClient
                $async = $sock.BeginConnect("127.0.0.1", $Port, $null, $null)
                $async.AsyncWaitHandle.WaitOne(2000) | Out-Null
                if ($sock.Connected) {
                    $sock.Close()
                    Write-Host "  $Name TCP health check OK (port $Port)" -ForegroundColor Green
                    return
                }
                $sock.Close()
            } catch {}
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
        throw "$Name did not become healthy on port $Port within ${TimeoutSeconds}s (TCP check)"
    }

    $url = "http://127.0.0.1:$Port/$HealthPath"
    do {
        try {
            $params = @{
                Uri = $url
                UseBasicParsing = $true
                TimeoutSec = 2
            }
            if ($Headers.Count -gt 0) {
                $params.Headers = $Headers
            }
            $r = Invoke-WebRequest @params
            if ($r.StatusCode -eq 200) { return }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    } while ((Get-Date) -lt $deadline)

    throw "$Name did not become healthy on port $Port within ${TimeoutSeconds}s (checked: $url)"
}

function New-ChatBody {
    param([string]$Model = "gpt-4o-mini")

    return (@{
        model = $Model
        messages = @(@{
            role = "user"
            content = "benchmark preflight"
        })
    } | ConvertTo-Json -Depth 8 -Compress)
}

function Invoke-Preflight {
    param(
        [string]$Name,
        [int]$Port,
        [string]$Model = "gpt-4o-mini",
        [string]$Suffix = "v1",
        [string]$Path = "chat/completions",
        [string]$AuthToken = "sk-bench-test-key",
        [hashtable]$ExtraHeaders = @{}
    )

    $url = "http://127.0.0.1:$Port/$Suffix/$Path"
    $body = New-ChatBody -Model $Model
    $headers = @{Authorization = "Bearer $AuthToken"}
    foreach ($kv in $ExtraHeaders.GetEnumerator()) {
        $headers[$kv.Key] = $kv.Value
    }
    $lastError = $null
    for ($retry = 0; $retry -lt 12; $retry++) {
        try {
            $r = Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 10
            if ($r.StatusCode -lt 200 -or $r.StatusCode -gt 299) {
                throw "$Name preflight returned HTTP $($r.StatusCode)"
            }
            Write-Host "  $Name preflight OK (HTTP $($r.StatusCode))" -ForegroundColor DarkGray
            return
        }
        catch {
            $lastError = $_.Exception.Message
            if ($retry -lt 11) { Start-Sleep -Milliseconds 2500 }
        }
    }
    throw "$Name preflight failed at $url after 12 retries. $lastError"
}

function Invoke-Warmup {
    param(
        [string]$Name,
        [int]$Port,
        [int]$WarmupRequests = 25,
        [string]$Model = "gpt-4o-mini",
        [string]$Suffix = "v1",
        [string]$Path = "chat/completions",
        [string]$AuthToken = "sk-bench-test-key",
        [hashtable]$ExtraHeaders = @{}
    )

    if ($WarmupRequests -le 0) { return }

    $url = "http://127.0.0.1:$Port/$Suffix/$Path"
    $body = New-ChatBody -Model $Model
    $headers = @{Authorization = "Bearer $AuthToken"}
    foreach ($kv in $ExtraHeaders.GetEnumerator()) {
        $headers[$kv.Key] = $kv.Value
    }
    for ($i = 0; $i -lt $WarmupRequests; $i++) {
        try {
            Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 10 | Out-Null
        }
        catch {
            throw "$Name warmup failed at request $($i + 1). $($_.Exception.Message)"
        }
    }
    Write-Host "  $Name warmup: $WarmupRequests requests" -ForegroundColor DarkGray
}

function Find-AuroraSourceDir {
    param([string]$RepoRoot)
    $candidates = @(
        (Join-Path $RepoRoot "apps\aurora"),
        (Join-Path $RepoRoot "cmd\aurora")
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "main.go")) { return $c }
    }
    Write-Host "  Aurora source not found in repo - will use pre-built binary" -ForegroundColor Yellow
    return $null
}

function Find-BifrostBinary {
    if ($env:BIFROST_EXE_PATH -and (Test-Path $env:BIFROST_EXE_PATH)) {
        return $env:BIFROST_EXE_PATH
    }
    $npxCache = Join-Path $env:LOCALAPPDATA "bifrost"
    if (Test-Path $npxCache) {
        $found = Get-ChildItem -Path $npxCache -Recurse -Filter "bifrost-http.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($found) { return $found }

        $found0 = Get-ChildItem -Path $npxCache -Recurse -Filter "bifrost-http.exe-0" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
        if ($found0) {
            $exePath = [System.IO.Path]::ChangeExtension($found0, ".exe")
            if (-not (Test-Path $exePath)) {
                Copy-Item -Path $found0 -Destination $exePath -Force
                Write-Host "  Fixed bifrost binary: $found0 -> $exePath" -ForegroundColor DarkYellow
            }
            else {
                $exePath = Join-Path (Split-Path $found0) "bifrost-http.exe"
            }
            return $exePath
        }
    }
    return $null
}

function Start-GatewayProcess {
    param(
        [string]$ExePath,
        [hashtable]$EnvOverrides = @{},
        [string[]]$ExtraArgs = @(),
        [string]$LogPath = "",
        [string]$WorkingDir = "",
        [switch]$NewWindow,
        [switch]$SuppressOutput
    )

    foreach ($key in $EnvOverrides.Keys) {
        Set-Item -LiteralPath "env:$key" -Value $EnvOverrides[$key]
    }

    $startArgs = @{
        FilePath = $ExePath
        PassThru = $true
    }
    if ($WorkingDir) { $startArgs.WorkingDirectory = $WorkingDir }
    if ($ExtraArgs -and $ExtraArgs.Count -gt 0) { $startArgs.ArgumentList = $ExtraArgs }

    if ($NewWindow) {
        $envBlock = ""
        foreach ($key in $EnvOverrides.Keys) {
            $envBlock += "`$env:$key='$($EnvOverrides[$key])'; "
        }
        $argStr = ($ExtraArgs | ForEach-Object { "'$_'" }) -join " "
        $cmd = "$envBlock & '$ExePath' $argStr"
        $sbArgs = @{ FilePath = "powershell"; ArgumentList = "-NoExit", "-WindowStyle Normal", "-Command", $cmd; PassThru = $true }
        if ($WorkingDir) { $sbArgs.WorkingDirectory = $WorkingDir }
        return Start-Process @sbArgs
    }

    $hasArgs = $ExtraArgs -and $ExtraArgs.Count -gt 0
    if ($SuppressOutput) {
        $errStream = [System.IO.Path]::GetTempFileName()
        $sa = @{ FilePath = $ExePath; RedirectStandardOutput = 'NUL'; RedirectStandardError = $errStream; PassThru = $true }
        if ($hasArgs) { $sa.ArgumentList = $ExtraArgs }
        if ($WorkingDir) { $sa.WorkingDirectory = $WorkingDir }
        $proc = Start-Process @sa
        $proc | Add-Member -NotePropertyName "SuppressErrFile" -NotePropertyValue $errStream -Force
        return $proc
    }

    if ($LogPath -and $LogPath.Trim() -ne "") {
        $errLog = "$LogPath.err"
        $sa = @{ FilePath = $ExePath; RedirectStandardOutput = $LogPath; RedirectStandardError = $errLog; PassThru = $true }
        if ($hasArgs) { $sa.ArgumentList = $ExtraArgs }
        if ($WorkingDir) { $sa.WorkingDirectory = $WorkingDir }
        return Start-Process @sa
    }

    $sa = @{ FilePath = $ExePath; PassThru = $true }
    if ($hasArgs) { $sa.ArgumentList = $ExtraArgs }
    if ($WorkingDir) { $sa.WorkingDirectory = $WorkingDir }
    return Start-Process @sa
}

function Stop-GatewayProcess {
    param($Process)

    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
    }
    if ($null -ne $Process -and $Process.SuppressErrFile) {
        Remove-Item -LiteralPath $Process.SuppressErrFile -Force -ErrorAction SilentlyContinue
    }
}

function Build-BenchCli {
    param([string]$BenchDir)

    $cliSrc = Join-Path $BenchDir "tools\benchmark-cli"
    $output = Join-Path (Join-Path $BenchDir "bin") "aurora-bench-cli.exe"

    if (-not (Test-Path (Join-Path $cliSrc "main.go"))) {
        throw "Benchmark CLI source not found at $cliSrc"
    }

    if (Test-Path $output) {
        $binTime = (Get-Item $output).LastWriteTime
        $newer = Get-ChildItem -Path $cliSrc -Recurse -Include "*.go" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $binTime }
        if (-not $newer) {
            return $output
        }
        Write-Host "Benchmark CLI source changed, rebuilding..." -ForegroundColor Yellow
    }

    Write-Host "Building benchmark CLI..." -ForegroundColor Yellow
    Push-Location $BenchDir
    try {
        go build -o $output $cliSrc
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path $output)) {
        throw "Benchmark CLI build failed"
    }
    Write-Host "Benchmark CLI built: $output" -ForegroundColor Green
    return $output
}

function Stop-ProcessOnPort {
    param([int[]]$Ports)

    foreach ($port in $Ports) {
        try {
            $connections = netstat -ano | Select-String "LISTENING" | Select-String ":$port "
            foreach ($conn in $connections) {
                $parts = $conn -split '\s+'
                $procId = $parts[-1]
                if (-not $procId -or $procId -notmatch '^\d+$') { continue }
                $skip = $false
                try { $p = Get-Process -Id $procId; if ($p.ProcessName -match 'docker|wsl|com\.docker') { $skip = $true } } catch {}
                if ($skip) { continue }
                Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                Write-Host "  Killed process $procId on port $port" -ForegroundColor DarkYellow
            }
        } catch {}
    }
}

function Stop-BenchProcesses {
    param(
        [int[]]$Ports = @(8080, 8081, 9099),
        [string[]]$ProcessNames = @("mock-server", "aurora-bench", "bifrost-http", "aurora-bench-cli", "k6")
    )

    foreach ($name in $ProcessNames) {
        try {
            Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                Write-Host "  Killed $name (PID $($_.Id))" -ForegroundColor DarkYellow
            }
        } catch {}
    }

    Stop-ProcessOnPort -Ports $Ports
}

Export-ModuleMember -Function Wait-ForHealth, New-ChatBody, Invoke-Preflight, Invoke-Warmup, `
    Find-AuroraSourceDir, Find-BifrostBinary, Start-GatewayProcess, Stop-GatewayProcess, Build-BenchCli, Stop-ProcessOnPort, Stop-BenchProcesses
