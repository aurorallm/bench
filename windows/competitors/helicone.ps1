return @{
    Name                  = "helicone"
    DisplayName           = "Helicone AI Gateway"
    Language              = "Rust"
    DefaultPort           = 8585
    HealthCheckType       = "tcp"
    HealthPath            = ""
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "ai"
    PreflightPath         = "chat/completions"
    PreflightModel        = "openai/gpt-4o-mini"
    BenchmarkModel        = "openai/gpt-4o-mini"
    BenchmarkPath         = "ai/chat/completions"
    Type                  = "docker"

    Install = {
        param($BenchDir, $RepoRoot)
        $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
        if (-not $dockerCmd) {
            throw "Docker not found. Install Docker to use Helicone competitor."
        }
        Write-Host "Helicone via Docker (helicone/ai-gateway)..." -ForegroundColor Yellow
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

        docker rm -f helicone-bench 2>$null

        $mockPort = ($MockUrl -split ':')[-1]
        $dockerMockUrl = "http://host.docker.internal:${mockPort}"

        $configPath = Join-Path $ResultsDir "helicone.yaml"
        $configContent = @"
providers:
  openai:
    models:
      - "gpt-4o-mini"
    base-url: "${dockerMockUrl}/v1"
"@
        Set-Content -Path $configPath -Value $configContent -NoNewline

        $extraArgs = @(
            "run", "-d", "--rm", "--name", "helicone-bench",
            "--log-driver", "none",
            "-p", "${Port}:8080",
            "-e", "OPENAI_API_KEY=$ApiKey",
            "-e", "RUST_LOG=off",
            "-v", "${configPath}:/app/config.yaml",
            "helicone/ai-gateway:latest",
            "/usr/local/bin/ai-gateway", "--config", "/app/config.yaml"
        )
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "Helicone is Docker-based (helicone/ai-gateway image) - ~41 MB Rust binary",
        "Auth check: bearer token verified against OPENAI_API_KEY (same as Aurora)",
        "RUST_LOG=error - only error-level logging, telemetry disabled",
        "Non-essential features disabled: no observability, no caching",
        "HTTP connection via Docker bridge - slight overhead vs native process"
    )
}
