return @{
    Name                  = "helicone-native"
    DisplayName           = "Helicone AI Gateway (Native)"
    Language              = "Rust"
    DefaultPort           = 8585
    HealthCheckType       = "tcp"
    HealthPath            = ""
    HealthTimeoutSeconds  = 30
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    BenchmarkModel        = "gpt-4o-mini"
    BenchmarkPath         = "v1/chat/completions"
    Type                  = "binary"

    Install = {
        param($BenchDir, $RepoRoot)
        $exeDir = Join-Path $BenchDir "bin\windows"
        $exePath = Join-Path $exeDir "helicone-gateway"

        if (Test-Path $exePath) {
            Write-Host "  Helicone native binary: $exePath ($((Get-Item $exePath).Length/1MB).ToString('F1') MB)" -ForegroundColor Green
            return $exePath
        }

        $isWin = $env:OS -match "Windows"
        if ($isWin) {
            Write-Host "  Helicone native binary is Linux-only. Use 'helicone' (Docker) competitor on Windows." -ForegroundColor Yellow
            throw "Helicone native is Linux-only. Use 'helicone' (Docker) on Windows."
        }

        Write-Host "  Helicone binary not found. Downloading from GitHub releases..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $exeDir | Out-Null
        try {
            Write-Host "  Looking up latest Helicone release..." -ForegroundColor DarkGray
            $apiUrl = "https://api.github.com/repos/Helicone/ai-gateway/releases?per_page=1"
            $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 30
            if (-not $releases -or $releases.Count -eq 0) { throw "No releases found" }
            $release = $releases[0]
            $tag = $release.tag_name
            Write-Host "  Latest release: $tag" -ForegroundColor DarkGray

            $assetName = $release.assets.name | Where-Object { $_ -match 'linux-gnu\.tar\.xz$' -and $_ -notmatch 'sha256' -and $_ -notmatch '\.sha256$' } | Select-Object -First 1
            if (-not $assetName) { throw "No Linux amd64 tar.xz asset found in release $tag" }
            $downloadUrl = "https://github.com/Helicone/ai-gateway/releases/download/$tag/$assetName"

            $tarPath = Join-Path $exeDir "helicone.tar.xz"
            Write-Host "  Downloading: $assetName" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tarPath -UseBasicParsing -TimeoutSec 120

            if (Get-Command "tar" -ErrorAction SilentlyContinue) {
                tar -xJf $tarPath -C $exeDir 2>$null
            } else {
                Write-Host "  'tar' not found; trying 7z..." -ForegroundColor DarkYellow
                7z x $tarPath -o"$exeDir" -y | Out-Null
            }
            Remove-Item -Path $tarPath -Force

            $extracted = Get-ChildItem -Path $exeDir -Filter "ai-gateway" | Where-Object { -not $_.Extension } | Select-Object -First 1
            if (-not $extracted) { throw "No ai-gateway binary found in extracted archive" }
            Move-Item -Path $extracted.FullName -Destination $exePath -Force
            chmod +x $exePath 2>$null
            Write-Host "  Helicone extracted: $exePath ($((Get-Item $exePath).Length/1MB).ToString('F1') MB)" -ForegroundColor Green
            return $exePath
        } catch {
            Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Manual download: https://github.com/Helicone/ai-gateway/releases" -ForegroundColor Yellow
            throw "Helicone binary not found. Download from releases and place at $exePath"
        }
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $configPath = Join-Path $ResultsDir "helicone-config.yaml"
        $mockPort = ($MockUrl -split ':')[-1]

        $configContent = @"
providers:
  openai:
    models:
      - "gpt-4o-mini"
    base-url: "${MockUrl}/v1"
"@
        Set-Content -Path $configPath -Value $configContent -NoNewline

        $extraArgs = @("--config", $configPath)
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow -EnvOverrides @{
            "OPENAI_API_KEY" = $ApiKey
            "RUST_LOG" = "error"
        }
    }.GetNewClosure()

    FairnessNotes = @(
        "Helicone native binary auto-downloaded from GitHub releases (~22 MB Rust binary)",
        "Linux-only binary - use 'helicone' (Docker) competitor on Windows",
        "Auth check: Bearer token verified against OPENAI_API_KEY env var",
        "RUST_LOG=error - only error-level logging",
        "Config file generated with mock server upstream URL",
        "Native process (no Docker bridge overhead) on Linux/WSL"
    )
}
