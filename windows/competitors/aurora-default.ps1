return @{
    Name                  = "aurora-default"
    DisplayName           = "Aurora Gateway (default)"
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
        $logPath = Join-Path $ResultsDir "aurora-default-server.log"

        # Pure out-of-the-box defaults — no tuning env vars.
        # Code defaults are already bench-optimized:
        #   h2c always-on, HTTP_MAX_IDLE_CONNS=4096,
        #   HTTP_MAX_CONNS_PER_HOST=256, PROMPT_CACHE_MODE=off,
        #   all non-essential features disabled by default.
        $envOverrides = @{
            PORT                 = [string]$Port
            OPENAI_BASE_URL      = $MockUrl
            OPENAI_API_KEY       = $ApiKey
            AURORA_MASTER_KEY    = $ApiKey
        }

        return Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -LogPath $logPath -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "Aurora with out-of-the-box code defaults - no performance tuning env vars",
        "Code defaults already match bench-optimized settings for h2c, connection pool, prompt cache",
        "All non-essential features disabled by default in OSS build"
    )
}
