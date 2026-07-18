return @{
    Name                  = "litellm"
    DisplayName           = "LiteLLM Gateway"
    Language              = "Python"
    DefaultPort           = 8082
    HealthPath            = "health/liveliness"
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    Type                  = "pip"

    Install = {
        param($BenchDir, $RepoRoot)
        $litellmCmd = Get-Command "litellm" -ErrorAction SilentlyContinue
        if (-not $litellmCmd) {
            Write-Host "LiteLLM not found. Installing..." -ForegroundColor Yellow
            pip install litellm[proxy]
            $litellmCmd = Get-Command "litellm" -ErrorAction SilentlyContinue
            if (-not $litellmCmd) {
                throw "LiteLLM installation failed"
            }
        }
        Write-Host "LiteLLM found: $($litellmCmd.Source)" -ForegroundColor Green
        return $litellmCmd.Source
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $benchDir = $PSScriptRoot | Split-Path
        $cfgOut = Join-Path $ResultsDir "litellm-config.yaml"
        $configContent = @"
model_list:
  - model_name: "gpt-4o-mini"
    litellm_params:
      model: "openai/gpt-4o-mini"
      api_key: "$ApiKey"
      api_base: "$MockUrl/v1"

general_settings:
  master_key: null
  disable_spend_logs: true
  disable_error_logs: true
  disable_spend_updates: true
  disable_reset_budget: true
  disable_master_key_return: true
  disable_adding_master_key_hash_to_db: true

litellm_settings:
  num_retries: 0
  request_timeout: 60
  drop_params: true
  cache: false
  success_callback: []
  failure_callback: []
  callbacks: []

router_settings:
  disable_cooldowns: true
  routing_strategy: simple-shuffle
"@
        Set-Content -Path $cfgOut -Value $configContent -Force
        $extraArgs = @("--config", $cfgOut, "--port", [string]$Port, "--telemetry", "False")
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow -SuppressOutput -EnvOverrides @{
            "NO_DOCS" = "True"
            "NO_REDOC" = "True"
            "LITELLM_TELEMETRY" = "False"
            "DISABLE_ADMIN_UI" = "True"
            "LITELLM_LOG" = "CRITICAL"
        }
    }.GetNewClosure()

    FairnessNotes = @(
        "LiteLLM is Python-based - interpreter startup time is excluded (warmup happens first)",
        "Telemetry disabled (--telemetry False + LITELLM_TELEMETRY=False)",
        "Swagger/Redoc disabled (NO_DOCS=NO_REDOC=True)",
        "Admin UI disabled (DISABLE_ADMIN_UI=True), spend+error logs disabled in config",
        "Spend updates + budget reset + cooldowns disabled, cache off, empty callbacks",
        "Proxy overhead higher due to Python runtime vs Go"
    )
}
