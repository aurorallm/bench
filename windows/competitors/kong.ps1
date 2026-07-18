return @{
    Name                  = "kong"
    DisplayName           = "Kong AI Gateway"
    Language              = "Lua/Nginx"
    DefaultPort           = 8000
    HealthCheckType       = "tcp"
    HealthPath            = ""
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    BenchmarkPath         = "v1/chat/completions"
    Type                  = "docker"

    Install = {
        param($BenchDir, $RepoRoot)
        $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
        if (-not $dockerCmd) {
            throw "Docker not found. Install Docker to use Kong competitor."
        }
        Write-Host "Kong via Docker (kong:latest)..." -ForegroundColor Yellow
        return "docker"
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        # Ensure Docker is running (port cleanup may have killed Docker Desktop)
        $dockerOk = $false
        for ($i = 0; $i -lt 5; $i++) {
            $result = docker ps 2>&1 | Out-String
            if ($result -like "*CONTAINER*") { $dockerOk = $true; break }
            Write-Host "  Docker not responding, restarting Docker Desktop (attempt $($i+1))..." -ForegroundColor DarkYellow
            Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            Start-Sleep -Seconds 20
        }
        if (-not $dockerOk) { throw "Docker Desktop failed to start" }

        docker rm -f kong-bench 2>$null

        $mockPort = ($MockUrl -split ':')[-1]
        $template = Get-Content (Join-Path $PSScriptRoot "..\configs\kong-bench.yaml") -Raw
        $config = $template -replace 'MOCK_PORT', $mockPort

        $configPath = Join-Path $ResultsDir "kong.yaml"
        Set-Content -Path $configPath -Value $config -NoNewline

        $extraArgs = @(
            "run", "-d", "--rm", "--name", "kong-bench",
            "--log-driver", "none",
            "-p", "${Port}:8000",
            "-e", "KONG_DATABASE=off",
            "-e", "KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml",
            "-e", "KONG_PROXY_ACCESS_LOG=/dev/null",
            "-e", "KONG_PROXY_ERROR_LOG=/dev/null",
            "-e", "KONG_LOG_LEVEL=crit",
            "-e", "KONG_PLUGINS=cors",
            "-e", "KONG_ADMIN_LISTEN=off",
            "-e", "KONG_ADMIN_ACCESS_LOG=off",
            "-e", "KONG_ADMIN_ERROR_LOG=/dev/null",
            "-e", "KONG_STATUS_ACCESS_LOG=off",
            "-e", "KONG_STATUS_ERROR_LOG=/dev/null",
            "-v", "${configPath}:/kong/declarative/kong.yml",
            "kong:latest"
        )
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "Kong is Docker-based (kong:latest OSS image)",
        "DB-less mode - no Postgres/Cassandra dependency",
        "Minimal plugins (cors only), logs redirected to /dev/null, log_level=crit",
        "Admin API disabled (KONG_ADMIN_LISTEN=off), status API logs disabled",
        "Pure reverse proxy - no AI-specific plugins (OSS limitation)",
        "HTTP connection via Docker bridge - slight overhead vs native process"
    )
}
