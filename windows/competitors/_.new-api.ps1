return @{
    Name                  = "new-api"
    DisplayName           = "New API"
    Language              = "Go"
    DefaultPort           = 3001
    HealthCheckType       = ""
    HealthPath            = "api/status"
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    Type                  = "docker"

    Install = {
        param($BenchDir, $RepoRoot)
        $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
        if (-not $dockerCmd) {
            throw "Docker not found. Install Docker to use New API competitor."
        }
        Write-Host "New API via Docker (calciumion/new-api:latest)..." -ForegroundColor Yellow
        return "docker"
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $dockerOk = $false
        for ($i = 0; $i -lt 5; $i++) {
            $result = docker ps 2>&1 | Out-String
            if ($result -like "*CONTAINER*") { $dockerOk = $true; break }
            Write-Host "  Docker not responding, restarting Docker Desktop (attempt $($i+1))..." -ForegroundColor DarkYellow
            Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            Start-Sleep -Seconds 20
        }
        if (-not $dockerOk) { throw "Docker Desktop failed to start" }

        docker rm -f new-api-bench new-api-init 2>$null

        $mockPort = ($MockUrl -split ':')[-1]
        $dataDir = Join-Path $ResultsDir "new-api-data"
        $initFlag = Join-Path $dataDir "initialized.flag"

        if (-not (Test-Path $initFlag)) {
            $null = New-Item -ItemType Directory -Path $dataDir -Force
            Write-Host "  Initializing New API database..." -ForegroundColor DarkYellow

            # Start init container to get the SQLite DB
            docker run -d --rm --name new-api-init -p 3002:3000 calciumion/new-api:latest 2>$null
            $initReady = $false
            for ($i = 0; $i -lt 30; $i++) {
                Start-Sleep -Seconds 1
                try { $r = Invoke-WebRequest -Uri "http://localhost:3002/api/status" -UseBasicParsing -ErrorAction SilentlyContinue; if ($r.StatusCode -eq 200) { $initReady = $true; break } } catch {}
            }
            if (-not $initReady) { throw "New API init container did not become ready" }

            # Register admin user
            Invoke-RestMethod -Uri "http://localhost:3002/api/user/register" -Method Post -Body (@{username="root";password="adminadmin"} | ConvertTo-Json) -ContentType "application/json" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            # Copy DB and stop init container
            docker cp new-api-init:/data/one-api.db "$dataDir\one-api.db"
            docker stop new-api-init 2>$null

            # Patch DB via Alpine helper
            $nativeDataDir = (Resolve-Path $dataDir).Path
            docker pull alpine:latest 2>$null
            docker run -d --name na-helper -v "${nativeDataDir}:/data" alpine:latest sleep 30 2>$null
            docker exec na-helper apk add sqlite-libs sqlite 2>$null

            $userGroup = docker exec na-helper sqlite3 /data/one-api.db "SELECT [group] FROM users WHERE id = 1;"
            docker exec na-helper sqlite3 /data/one-api.db "UPDATE users SET role = 100, quota = 100000000 WHERE id = 1;"

            $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            docker exec na-helper sqlite3 /data/one-api.db "INSERT INTO channels (type, key, status, name, weight, created_time, base_url, models, [group], auto_ban) VALUES (1, 'sk-mock-key', 1, 'Mock OpenAI', 0, $ts, 'http://host.docker.internal:${mockPort}', 'gpt-4o-mini', '$userGroup', 1);"
            docker exec na-helper sqlite3 /data/one-api.db "INSERT INTO abilities ([group], model, channel_id, enabled, priority, weight) VALUES ('$userGroup', 'gpt-4o-mini', 1, 1, 0, 0);"
            docker exec na-helper sqlite3 /data/one-api.db "INSERT INTO tokens (user_id, key, status, name, created_time, accessed_time, remain_quota, unlimited_quota) VALUES (1, 'benchkey', 1, 'bench-token', $ts, $ts, 500000, 0);"

            docker stop na-helper 2>$null
            docker rm na-helper 2>$null

            Set-Content -Path $initFlag -Value "initialized" -NoNewline
            Write-Host "  New API database initialized (admin, channel, token)" -ForegroundColor Green
        }

        $nativeDataDir = (Resolve-Path $dataDir).Path
        $extraArgs = @(
            "run", "-d", "--rm", "--name", "new-api-bench",
            "--log-driver", "none",
            "-p", "${Port}:3000",
            "-v", "${nativeDataDir}:/data",
            "-e", "ERROR_LOG_ENABLED=false",
            "calciumion/new-api:latest"
        )
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "New API is Docker-based (calciumion/new-api image) - ~325 MB Go binary",
        "Pre-initialized SQLite database with admin user (role=100), channel, abilities",
        "Token key is 'benchkey' (no hyphens - use -ApiKey 'sk-benchkey' when running the benchmark)",
        "New API parses hyphens in API key as channel ID selectors; hyphens break routing",
        "Auth: Bearer token (sk-xxx) for inference requests via token key matching",
        "Error log disabled (ERROR_LOG_ENABLED=false), Docker log-driver none",
        "No Redis - SQLite mode, memory cache disabled",
        "HTTP connection via Docker bridge - slight overhead vs native process"
    )
}
