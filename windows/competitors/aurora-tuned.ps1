return @{
    Name                  = "aurora-tuned"
    DisplayName           = "Aurora Gateway (tuned)"
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
        Write-Host "  Aurora binary not found. Run 'aurora' competitor first to download it." -ForegroundColor Yellow
        throw "Aurora binary not found at $auroraExe"
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $logPath = Join-Path $ResultsDir "aurora-tuned-server.log"

        # Bench-mode tuning only — no feature disablements.
        # h2c always-on and connection pool defaults already match bench.
        $envOverrides = @{
            PORT                              = [string]$Port
            OPENAI_BASE_URL                   = $MockUrl
            OPENAI_API_KEY                    = $ApiKey
            AURORA_MASTER_KEY                 = $ApiKey

            AURORA_MINIMAL_BENCH_MODE         = "true"
            AURORA_CHAT_FAST_PATH_PASSTHROUGH = "true"
        }

        return Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -LogPath $logPath -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "Aurora with bench-mode tuning only - no explicit feature disablements",
        "AURORA_MINIMAL_BENCH_MODE=true + AURORA_CHAT_FAST_PATH_PASSTHROUGH=true",
        "h2c always-on and connection pool tuning are now code defaults"
    )
}
