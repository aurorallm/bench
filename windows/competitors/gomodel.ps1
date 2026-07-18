return @{
    Name                  = "gomodel"
    DisplayName           = "GoModel AI Gateway"
    Language              = "Go"
    DefaultPort           = 8091
    HealthPath            = "health"
    HealthTimeoutSeconds  = 30
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    Type                  = "docker"

    Install = {
        param($BenchDir, $RepoRoot)
        $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
        if (-not $dockerCmd) {
            throw "Docker not found. Install Docker to use GoModel competitor."
        }
        Write-Host "GoModel via Docker (enterpilot/gomodel:latest)..." -ForegroundColor Yellow
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

        docker rm -f gomodel-bench 2>$null

        $mockPort = ($MockUrl -split ':')[-1]
        $extraArgs = @(
            "run", "-d", "--rm", "--name", "gomodel-bench",
            "--log-driver", "none",
            "-p", "${Port}:8080",
            "-e", "GOMODEL_MASTER_KEY=$ApiKey",
            "-e", "OPENAI_API_KEY=$ApiKey",
            "-e", "OPENAI_BASE_URL=http://host.docker.internal:${mockPort}/v1",
            "-e", "LOGGING_ENABLED=false",
            "-e", "USAGE_ENABLED=false",
            "-e", "ADMIN_ENDPOINTS_ENABLED=false",
            "-e", "ADMIN_UI_ENABLED=false",
            "-e", "GUARDRAILS_ENABLED=false",
            "-e", "SWAGGER_ENABLED=false",
            "-e", "PPROF_ENABLED=false",
            "-e", "CLI_TOOLS_ENABLED=false",
            "-e", "COMBOS_ENABLED=false",
            "-e", "METRICS_ENABLED=false",
            "-e", "RESPONSE_CACHE_SIMPLE_ENABLED=false",
            "-e", "SEMANTIC_CACHE_ENABLED=false",
            "-e", "TOKEN_SAVER_ENABLED=false",
            "enterpilot/gomodel:latest"
        )
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "GoModel is Docker-based (enterpilot/gomodel image) - ~70 MB Go binary",
        "Auth check: Bearer token verified against GOMODEL_MASTER_KEY env var (same as Aurora)",
        "Single-binary Go gateway - no external dependencies, no telemetry",
        "Logging disabled (LOGGING_ENABLED=false), Docker log-driver none",
        "HTTP connection via Docker bridge - slight overhead vs native process",
        "OPENAI_BASE_URL set to mock server, model 'gpt-4o-mini' mapped to upstream"
    )
}
