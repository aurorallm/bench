return @{
    Name                  = "bifrost"
    DisplayName           = "Bifrost Gateway"
    Language              = "Go"
    DefaultPort           = 8080
    HealthPath            = "health"
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "openai/gpt-4o-mini"
    Type                  = "binary"

    Install = {
        param($BenchDir, $RepoRoot)
        $exePath = Find-BifrostBinary
        if (-not $exePath) {
            Write-Host "Bifrost binary not found. Install with:" -ForegroundColor Yellow
            Write-Host "  npx -y @maximhq/bifrost --help" -ForegroundColor Yellow
            Write-Host "Or set `$env:BIFROST_EXE_PATH" -ForegroundColor Yellow
            throw "Bifrost binary not found"
        }
        Write-Host "Bifrost found: $exePath" -ForegroundColor Green
        return $exePath
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $appDir = Join-Path $ResultsDir "bifrost-app"
        New-Item -ItemType Directory -Force -Path $appDir | Out-Null
        $configDir = Resolve-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "..") "configs")
        $configPath = Join-Path $configDir "bifrost-config.json"
        if (Test-Path $configPath) {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($config.providers.openai.network_config.base_url) {
                $config.providers.openai.network_config.base_url = $MockUrl
            }
            if ($config.providers.openai.keys[0].value) {
                $config.providers.openai.keys[0].value = $ApiKey
            }
            # Disable Web UI and request logging for minimal benchmark mode
            $config | Add-Member -Type NoteProperty -Name "config_store" -Value @{ "enabled" = $false } -Force
            if (-not ($config.PSObject.Properties.Name -contains "client")) {
                $config | Add-Member -Type NoteProperty -Name "client" -Value @{} -Force
            }
            $config.client.enable_logging = $false
            $config.client.disable_content_logging = $true
            $config | Add-Member -Type NoteProperty -Name "logs_store" -Value @{ "enabled" = $false; "type" = "sqlite" } -Force
            $config | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $appDir "config.json") -Encoding Ascii
            Write-Host "Bifrost config: base_url=$MockUrl, key=$ApiKey, minimal mode" -ForegroundColor DarkGray
        }
        $extraArgs = @("-port", [string]$Port, "-host", "127.0.0.1", "-app-dir", $appDir, "-log-level", "error")
        return Start-GatewayProcess -ExePath $ExePath -ExtraArgs $extraArgs -NewWindow:$NewWindow -SuppressOutput
    }.GetNewClosure()

    FairnessNotes = @(
        "Bifrost does provider catalog sync at startup (~3s) - excluded from measured time",
        "Uses SQLite for pricing records by default",
        "Log level set to error - only error messages, request + content logging disabled",
        "Web UI disabled (config_store.enabled=false), log store off, content logging off"
    )
}
