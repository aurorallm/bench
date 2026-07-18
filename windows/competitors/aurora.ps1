return @{
    Name                  = "aurora"
    DisplayName           = "Aurora Gateway"
    Language              = "Go"
    DefaultPort           = 8081
    HealthPath            = "health"
    HealthTimeoutSeconds  = 30
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    EnvVarPort            = "PORT"
    Type                  = "source"

    Install = {
        param($BenchDir, $RepoRoot)
        $auroraExe = Join-Path $BenchDir "bin\windows\aurora-bench.exe"
        if (Test-Path $auroraExe) {
            return $auroraExe
        }
        Write-Host "  Aurora binary not found. Downloading from GitHub releases..." -ForegroundColor Yellow
        $binDir = Join-Path $BenchDir "bin\windows"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        try {
            Write-Host "  Looking up latest Aurora release..." -ForegroundColor DarkGray
            $apiUrl = "https://api.github.com/repos/aurorallm/aurora/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
            $tag = $release.tag_name
            Write-Host "  Latest release: $tag" -ForegroundColor DarkGray
            $isWin = $env:OS -match "Windows"
            if ($isWin) {
                $assetName = $release.assets.name | Where-Object { $_ -match 'windows_amd64\.zip$' } | Select-Object -First 1
                if (-not $assetName) { throw "No Windows amd64 zip asset found in release $tag" }
                $downloadUrl = "https://github.com/aurorallm/aurora/releases/download/$tag/$assetName"
                $zipPath = Join-Path $binDir "aurora.zip"
                Write-Host "  Downloading: $assetName" -ForegroundColor DarkGray
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
                Write-Host "  Extracting..." -ForegroundColor DarkGray
                Expand-Archive -Path $zipPath -DestinationPath $binDir -Force
                Remove-Item -Path $zipPath -Force
                $extracted = Get-ChildItem -Path $binDir -Filter "*.exe" | Where-Object { $_.Name -like "aurora*" } | Sort-Object Length -Descending | Select-Object -First 1
                if (-not $extracted) { throw "No aurora*.exe found in extracted archive" }
                if ($extracted.FullName -ne $auroraExe) {
                    Move-Item -Path $extracted.FullName -Destination $auroraExe -Force
                }
            } else {
                $assetName = $release.assets.name | Where-Object { $_ -match 'linux_amd64\.tar\.gz$' } | Select-Object -First 1
                if (-not $assetName) { throw "No Linux amd64 tar.gz asset found in release $tag" }
                $downloadUrl = "https://github.com/aurorallm/aurora/releases/download/$tag/$assetName"
                $tarPath = Join-Path $binDir "aurora.tar.gz"
                Write-Host "  Downloading: $assetName" -ForegroundColor DarkGray
                Invoke-WebRequest -Uri $downloadUrl -OutFile $tarPath -UseBasicParsing -TimeoutSec 120
                tar -xzf $tarPath -C $binDir 2>$null
                Remove-Item -Path $tarPath -Force
                $extracted = Get-ChildItem -Path $binDir -Filter "aurora" | Where-Object { -not $_.Extension } | Select-Object -First 1
                if (-not $extracted) { throw "No aurora binary found in extracted archive" }
                Move-Item -Path $extracted.FullName -Destination $auroraExe -Force
                chmod +x $auroraExe 2>$null
            }
            Write-Host "  Aurora extracted: $auroraExe ($((Get-Item $auroraExe).Length/1MB).ToString('F1') MB)" -ForegroundColor Green
            return $auroraExe
        } catch {
            Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Manual download: https://github.com/aurorallm/aurora/releases" -ForegroundColor Yellow
            Write-Host "  Place the binary at: $auroraExe" -ForegroundColor Yellow
            throw "Aurora binary not available. Download from releases and place at $auroraExe"
        }
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $logPath = Join-Path $ResultsDir "aurora-server.log"
        $benchWorkDir = Join-Path $ResultsDir "aurora-workdir"
        New-Item -ItemType Directory -Force -Path $benchWorkDir | Out-Null
        $envOverrides = @{
            PORT                         = [string]$Port
            OPENAI_BASE_URL              = $MockUrl
            OPENAI_API_KEY               = $ApiKey
            AURORA_MASTER_KEY            = $ApiKey
            AURORA_MINIMAL_BENCH_MODE    = "true"
            AURORA_H2C_ENABLED           = "true"
            AURORA_CHAT_FAST_PATH_PASSTHROUGH = "true"
            HTTP_MAX_IDLE_CONNS          = "4096"
            HTTP_MAX_IDLE_CONNS_PER_HOST = "4096"
            HTTP_MAX_CONNS_PER_HOST      = "256"
            MODEL_LIST_URL               = ""

            STORAGE_TYPE                 = "sqlite"
            IDENTITY_ENABLED             = "false"
            GUARDRAILS_ENABLED           = "false"
            USAGE_ENABLED                = "false"
            LOGGING_ENABLED              = "false"
            METRICS_ENABLED              = "false"
            SEMANTIC_CACHE_ENABLED       = "false"
            RESPONSE_CACHE_SIMPLE_ENABLED = "false"
            TOKEN_SAVER_ENABLED          = "false"
            PROMPT_CACHE_MODE            = "off"
            SWAGGER_ENABLED              = "false"
            PPROF_ENABLED                = "false"
            ENABLE_ANTHROPIC_INGRESS     = "false"
            CLI_TOOLS_ENABLED            = "false"
            COMBOS_ENABLED               = "false"
            ADMIN_ENDPOINTS_ENABLED      = "false"
            ADMIN_UI_ENABLED             = "false"
        }

        return Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -LogPath $logPath -WorkingDir $benchWorkDir -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "AURORA_MINIMAL_BENCH_MODE=true disables request logging + body snapshot + usage + tightens timeouts",
        "AURORA_CHAT_FAST_PATH_PASSTHROUGH=true bypasses JSON decode/re-encode for simple pass-through",
        "AURORA_H2C_ENABLED=true enables HTTP/2 multiplexing - proven -28% P999 latency",
        "PROMPT_CACHE_MODE=off skips prompt cache breakpoint injection",
        "All features disabled: guardrails, cache, token saver, admin, identity, swagger, combos, anthropic ingress",
        "HTTP pool: 4096 idle conns, 4096 per host, 256 max per host",
        "Binary auto-downloaded from github.com/aurorallm/aurora/releases"
    )
}
