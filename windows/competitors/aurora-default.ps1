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
        $envOverrides = @{
            PORT                               = [string]$Port
            OPENAI_BASE_URL                    = $MockUrl
            OPENAI_API_KEY                     = $ApiKey
            AURORA_MASTER_KEY                  = $ApiKey
            AURORA_MINIMAL_BENCH_MODE          = "true"
            AURORA_H2C_ENABLED                 = "true"
            AURORA_CHAT_FAST_PATH_PASSTHROUGH  = "true"
            HTTP_MAX_IDLE_CONNS                = "4096"
            HTTP_MAX_IDLE_CONNS_PER_HOST       = "4096"
            HTTP_MAX_CONNS_PER_HOST            = "256"
            MODEL_LIST_URL                     = ""
            STORAGE_TYPE                       = "sqlite"
            IDENTITY_ENABLED                   = "false"
            GUARDRAILS_ENABLED                 = "false"
            USAGE_ENABLED                      = "false"
            LOGGING_ENABLED                    = "false"
            METRICS_ENABLED                    = "false"
            SEMANTIC_CACHE_ENABLED             = "false"
            RESPONSE_CACHE_SIMPLE_ENABLED      = "false"
            TOKEN_SAVER_ENABLED                = "false"
            PROMPT_CACHE_MODE                  = "off"
            SWAGGER_ENABLED                    = "false"
            ENABLE_ANTHROPIC_INGRESS           = "false"
            CLI_TOOLS_ENABLED                  = "false"
            COMBOS_ENABLED                     = "false"
            ADMIN_ENDPOINTS_ENABLED            = "false"
            ADMIN_UI_ENABLED                   = "false"
        }

        return Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -LogPath $logPath -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "Aurora with ALL features enabled at max throughput settings for apples-to-apples comparison",
        "Same env vars as aurora and aurora-tuned: MINIMAL_BENCH_MODE, H2C, FAST_PATH, all features disabled",
        "Default variant kept for reference; all competitors now run identical perf-optimized config"
    )
}
