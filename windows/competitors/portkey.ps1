return @{
    Name                  = "portkey"
    DisplayName           = "Portkey AI Gateway"
    Language              = "TypeScript"
    DefaultPort           = 8787
    HealthPath            = "v1/models"
    HealthTimeoutSeconds  = 60
    HealthCheckType       = "tcp"
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    Type                  = "npm"
    Headers               = @{
        'x-portkey-provider' = 'openai'
        'x-portkey-custom-host' = '${MOCK_URL}/v1'
    }

    Install = {
        param($BenchDir, $RepoRoot)
        $npxCmd = Get-Command "npx.cmd" -ErrorAction SilentlyContinue
        if (-not $npxCmd) {
            throw "npx not found. Install Node.js first."
        }
        Write-Host ("Portkey gateway via " + $npxCmd.Source) -ForegroundColor Green
        return $npxCmd.Source
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $extraArgs = @("@portkey-ai/gateway")
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow -SuppressOutput -EnvOverrides @{
            "OPENAI_API_KEY" = $ApiKey
            "NODE_ENV" = "production"
        }
    }.GetNewClosure()

    FairnessNotes = @(
        "Portkey port 8787 is hardcoded (not configurable via CLI)",
        "Routing via x-portkey-provider + x-portkey-custom-host headers",
        "Built on Hono framework, runs as Node.js process",
        "Self-hosted mode is headless - no UI, no telemetry (OSS gateway)"
    )
}
