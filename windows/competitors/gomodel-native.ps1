return @{
    Name                  = "gomodel-native"
    DisplayName           = "GoModel AI Gateway (Native)"
    Language              = "Go"
    DefaultPort           = 8091
    HealthPath            = "health"
    HealthTimeoutSeconds  = 15
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    EnvVarPort            = "PORT"
    Type                  = "source"

    Install = {
        param($BenchDir, $RepoRoot)
        $gomodelExe = Join-Path $BenchDir "bin\windows\gomodel.exe"
        if (Test-Path $gomodelExe) {
            Write-Host "  GoModel native binary found: $gomodelExe" -ForegroundColor Green
            return $gomodelExe
        }
        Write-Host "  GoModel binary not found. Downloading from GitHub releases..." -ForegroundColor Yellow
        $binDir = Join-Path $BenchDir "bin\windows"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        try {
            Write-Host "  Looking up latest GoModel release..." -ForegroundColor DarkGray
            $apiUrl = "https://api.github.com/repos/ENTERPILOT/GoModel/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
            $tag = $release.tag_name
            Write-Host "  Latest release: $tag" -ForegroundColor DarkGray

            $isWin = $env:OS -match "Windows"
            if ($isWin) {
                $assetName = $release.assets.name | Where-Object { $_ -match 'windows_amd64\.zip$' } | Select-Object -First 1
                if (-not $assetName) { throw "No Windows amd64 zip asset found in release $tag" }
                $downloadUrl = "https://github.com/ENTERPILOT/GoModel/releases/download/$tag/$assetName"
                $zipPath = Join-Path $binDir "gomodel.zip"
                Write-Host "  Downloading: $assetName" -ForegroundColor DarkGray
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
                Write-Host "  Extracting..." -ForegroundColor DarkGray
                Expand-Archive -Path $zipPath -DestinationPath $binDir -Force
                Remove-Item -Path $zipPath -Force
                $extracted = Get-ChildItem -Path $binDir -Filter "*.exe" | Where-Object { $_.Name -like "gomodel*" } | Sort-Object Length -Descending | Select-Object -First 1
                if (-not $extracted) { throw "No gomodel*.exe found in extracted archive" }
                if ($extracted.FullName -ne $gomodelExe) {
                    Move-Item -Path $extracted.FullName -Destination $gomodelExe -Force
                }
            } else {
                $assetName = $release.assets.name | Where-Object { $_ -match 'linux_amd64\.tar\.gz$' } | Select-Object -First 1
                if (-not $assetName) { throw "No Linux amd64 tar.gz asset found in release $tag" }
                $downloadUrl = "https://github.com/ENTERPILOT/GoModel/releases/download/$tag/$assetName"
                $tarPath = Join-Path $binDir "gomodel.tar.gz"
                Write-Host "  Downloading: $assetName" -ForegroundColor DarkGray
                Invoke-WebRequest -Uri $downloadUrl -OutFile $tarPath -UseBasicParsing -TimeoutSec 120
                tar -xzf $tarPath -C $binDir 2>$null
                Remove-Item -Path $tarPath -Force
                $extracted = Get-ChildItem -Path $binDir -Filter "gomodel" | Where-Object { -not $_.Extension } | Select-Object -First 1
                if (-not $extracted) { throw "No gomodel binary found in extracted archive" }
                Move-Item -Path $extracted.FullName -Destination $gomodelExe -Force
                chmod +x $gomodelExe 2>$null
            }
            Write-Host "  GoModel downloaded: $gomodelExe ($((Get-Item $gomodelExe).Length/1MB).ToString('F1') MB)" -ForegroundColor Green
            return $gomodelExe
        } catch {
            Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Manual download: https://github.com/ENTERPILOT/GoModel/releases" -ForegroundColor Yellow
            throw "GoModel binary not found. Download from releases and place at $gomodelExe"
        }
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $logPath = Join-Path $ResultsDir "gomodel-server.log"
        $envOverrides = @{
            PORT                = [string]$Port
            GOMODEL_MASTER_KEY  = $ApiKey
            OPENAI_API_KEY      = $ApiKey
            OPENAI_BASE_URL     = $MockUrl
            LOGGING_ENABLED     = "false"
            USAGE_ENABLED       = "false"
            ADMIN_ENDPOINTS_ENABLED = "false"
            ADMIN_UI_ENABLED    = "false"
            METRICS_ENABLED     = "false"
            SWAGGER_ENABLED     = "false"
            GUARDRAILS_ENABLED  = "false"
        }
        return Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -LogPath $logPath -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "GoModel native Windows binary auto-downloaded from GitHub releases",
        "Auth check: Bearer token verified against GOMODEL_MASTER_KEY env var (same as Aurora)",
        "Single-binary Go gateway - no external dependencies, no telemetry",
        "Same feature disables as Docker version: logging, usage, admin, metrics, swagger, guardrails",
        "Native process (no Docker overhead) - apples-to-apples with Aurora native"
    )
}
