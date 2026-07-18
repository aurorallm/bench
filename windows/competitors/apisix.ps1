return @{
    Name                  = "apisix"
    DisplayName           = "Apache APISIX"
    Language              = "Lua/Nginx"
    DefaultPort           = 9080
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
            throw "Docker not found. Install Docker to use APISIX competitor."
        }
        Write-Host "Apache APISIX via Docker (apache/apisix)..." -ForegroundColor Yellow
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

        docker rm -f apisix-bench 2>$null

        $mockPort = ($MockUrl -split ':')[-1]

        $configYaml = @"
deployment:
  role: data_plane
  role_data_plane:
    config_provider: yaml
apisix:
  enable_admin: false
plugins: []
nginx_config:
  main_config: |
    access_log /dev/null;
    error_log /dev/null crit;
  http_config: |
    access_log /dev/null;
    error_log /dev/null crit;
"@
        $configYamlPath = Join-Path $ResultsDir "apisix-config.yaml"
        Set-Content -Path $configYamlPath -Value $configYaml -NoNewline

        $template = Get-Content (Join-Path $PSScriptRoot "..\configs\apisix-bench.yaml") -Raw
        $apisixYaml = $template -replace 'MOCK_PORT', $mockPort

        $apisixYamlPath = Join-Path $ResultsDir "apisix.yaml"
        Set-Content -Path $apisixYamlPath -Value $apisixYaml -NoNewline

        $extraArgs = @(
            "run", "-d", "--rm", "--name", "apisix-bench",
            "--log-driver", "none",
            "-p", "${Port}:9080",
            "-e", "APISIX_STAND_ALONE=true",
            "-v", "${configYamlPath}:/usr/local/apisix/conf/config.yaml",
            "-v", "${apisixYamlPath}:/usr/local/apisix/conf/apisix.yaml",
            "apache/apisix"
        )
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "APISIX is Docker-based (apache/apisix OSS image)",
        "Standalone mode - no etcd dependency",
        "All plugins disabled (plugins: []), admin API disabled, nginx logs to /dev/null",
        "Pure reverse proxy - no AI-specific plugins configured (fair baseline)",
        "HTTP connection via Docker bridge - slight overhead vs native process"
    )
}
