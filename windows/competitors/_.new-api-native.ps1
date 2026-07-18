return @{
    Name                  = "new-api-native"
    DisplayName           = "New API (Native)"
    Language              = "Go"
    DefaultPort           = 3001
    HealthPath            = "api/status"
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    Type                  = "binary"

    Install = {
        param($BenchDir, $RepoRoot)
        $exePath = Join-Path $BenchDir "bin\windows\new-api.exe"
        if (-not (Test-Path $exePath)) {
            Write-Host "New API binary not found. Download manually from:" -ForegroundColor Yellow
            Write-Host "  https://github.com/QuantumNous/new-api/releases" -ForegroundColor Yellow
            throw "New API binary not found at $exePath"
        }
        Write-Host "New API native binary: $exePath ($((Get-Item $exePath).Length/1MB).ToString('F1') MB)" -ForegroundColor Green
        return $exePath
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $logDir = Join-Path $ResultsDir "new-api-logs"
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null

        $dataDir = Join-Path $ResultsDir "new-api-data"
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

        $envOverrides = @{
            ERROR_LOG_ENABLED       = "false"
            MEMORY_CACHE_ENABLED    = "true"
            GENERATE_DEFAULT_TOKEN  = "true"
            SESSION_SECRET          = "bench-bench-bench"
            BATCH_UPDATE_ENABLED    = "false"
            GIN_MODE                = "release"
        }
        $extraArgs = @("--port", [string]$Port, "--log-dir", $logDir)

        $proc = Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -ExtraArgs $extraArgs -NewWindow:$NewWindow

        $baseUrl = "http://127.0.0.1:${Port}"
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            try {
                $r = Invoke-WebRequest -Uri "${baseUrl}/api/status" -UseBasicParsing -ErrorAction SilentlyContinue
                if ($r.StatusCode -eq 200) { $ready = $true; break }
            } catch {}
        }
        if (-not $ready) { throw "New API native did not become ready on port $Port" }

        $initFlag = Join-Path $dataDir "initialized.flag"
        if (-not (Test-Path $initFlag)) {
            Write-Host "  Initializing New API (admin, channel, token)..." -ForegroundColor DarkYellow

            Invoke-RestMethod -Uri "${baseUrl}/api/user/register" -Method Post `
                -Body (@{username="root";password="adminadmin"} | ConvertTo-Json) `
                -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 2

            $login = Invoke-RestMethod -Uri "${baseUrl}/api/user/login" -Method Post `
                -Body (@{username="root";password="adminadmin"} | ConvertTo-Json) `
                -ContentType "application/json" -ErrorAction Stop
            $sessionToken = $login.token

            $authHeader = @{ "Authorization" = "Bearer $sessionToken" }

            $mockPort = ($MockUrl -split ':')[-1]
            $channelBody = @{
                type       = 1
                key        = "sk-mock-key"
                name       = "Mock OpenAI"
                base_url   = "http://127.0.0.1:${mockPort}"
                models     = "gpt-4o-mini"
                weight     = 0
                auto_ban   = 1
            } | ConvertTo-Json
            Invoke-RestMethod -Uri "${baseUrl}/api/channel/" -Method Post `
                -Body $channelBody -ContentType "application/json" `
                -Headers $authHeader -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 1

            $tokenBody = @{
                name            = "bench-token"
                remain_quota    = 500000
                unlimited_quota = $false
            } | ConvertTo-Json
            $tokenResp = Invoke-RestMethod -Uri "${baseUrl}/api/token/" -Method Post `
                -Body $tokenBody -ContentType "application/json" `
                -Headers $authHeader -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1

            Set-Content -Path $initFlag -Value "initialized" -NoNewline
            Write-Host "  New API initialized (admin, channel, token)" -ForegroundColor Green
        }

        return $proc
    }.GetNewClosure()

    FairnessNotes = @(
        "New API native Windows binary (137 MB) from official GitHub releases",
        "Pre-initialized SQLite database with admin user, channel, and token via API",
        "Memory cache enabled (MEMORY_CACHE_ENABLED=true), error logs disabled",
        "No Redis - SQLite mode with GENERATE_DEFAULT_TOKEN=true",
        "Native process (no Docker overhead) - apples-to-apples comparison"
    )
}
