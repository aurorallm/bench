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
        "Aurora with h2c + connection pool tuning + full feature disablement for max throughput",
        "AURORA_MINIMAL_BENCH_MODE=true + AURORA_CHAT_FAST_PATH_PASSTHROUGH=true + PROMPT_CACHE_MODE=off",
        "All features disabled: guardrails, cache, token saver, admin, identity, swagger, combos, anthropic ingress",
        "h2c enables HTTP/2 multiplexing over cleartext, 4096 idle conns, 256 max per host"
    )
}
