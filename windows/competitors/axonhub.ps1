$AxonHubTag = "v1.0.0-beta5"

return @{
    Name                  = "axonhub"
    DisplayName           = "AxonHub Gateway"
    Language              = "Go"
    DefaultPort           = 8090
    HealthPath            = "admin/system/status"
    HealthTimeoutSeconds  = 60
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    EnvVarPort            = "AXONHUB_SERVER_PORT"
    Type                  = "binary"

    Install = {
        param($BenchDir, $RepoRoot)
        $axonhubExe = Join-Path $BenchDir "bin\windows\axonhub.exe"
        if (Test-Path $axonhubExe) {
            Write-Host "  AxonHub binary: $axonhubExe ($((Get-Item $axonhubExe).Length/1MB).ToString('F1') MB)" -ForegroundColor DarkGray
            return $axonhubExe
        }

        Write-Host "  AxonHub binary not found. Downloading from GitHub releases..." -ForegroundColor Yellow
        $binDir = Join-Path $BenchDir "bin\windows"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null

        try {
            $tag = $AxonHubTag
            $version = $tag -replace '^v', ''
            $zipName = "axonhub_${version}_windows_amd64.zip"
            $downloadUrl = "https://github.com/looplj/axonhub/releases/download/$tag/$zipName"
            $zipPath = Join-Path $binDir "axonhub.zip"

            Write-Host "  Downloading: $zipName" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120

            Write-Host "  Extracting..." -ForegroundColor DarkGray
            $extractDir = Join-Path $binDir "axonhub-extract"
            New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
            Remove-Item -Path $zipPath -Force

            $extracted = Get-ChildItem -Path $extractDir -Recurse -Filter "axonhub.exe" | Select-Object -First 1
            if (-not $extracted) {
                throw "No axonhub.exe found in extracted archive"
            }
            Move-Item -Path $extracted.FullName -Destination $axonhubExe -Force
            Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue

            Write-Host "  AxonHub downloaded: $axonhubExe ($((Get-Item $axonhubExe).Length/1MB).ToString('F1') MB)" -ForegroundColor Green
            return $axonhubExe
        } catch {
            Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Manual download: https://github.com/looplj/axonhub/releases/tag/$AxonHubTag" -ForegroundColor Yellow
            Write-Host "  Place the binary at: $axonhubExe" -ForegroundColor Yellow
            throw "AxonHub binary not available"
        }
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        $logPath = Join-Path $ResultsDir "axonhub-server.log"
        $benchWorkDir = Join-Path $ResultsDir "axonhub-workdir"
        New-Item -ItemType Directory -Force -Path $benchWorkDir | Out-Null

        $envOverrides = @{
            AXONHUB_SERVER_PORT                = [string]$Port
            AXONHUB_SERVER_DEBUG               = "false"
            AXONHUB_SERVER_REQUEST_TIMEOUT     = "60s"
            AXONHUB_SERVER_LLM_REQUEST_TIMEOUT = "60s"
            AXONHUB_SERVER_API_AUTH_ALLOW_NO_AUTH = "true"
            AXONHUB_LOG_LEVEL                  = "fatal"
            AXONHUB_LOG_ENCODING               = "console"
            AXONHUB_LOG_OUTPUT                 = "stdio"
            AXONHUB_METRICS_ENABLED            = "false"
            AXONHUB_DB_DIALECT                 = "sqlite3"
            AXONHUB_DB_MAX_OPEN_CONNS          = "5"
            AXONHUB_DB_MAX_IDLE_CONNS          = "2"
            AXONHUB_CACHE_MODE                 = "memory"
            AXONHUB_GC_CRON                    = ""
            AXONHUB_PROVIDER_QUOTA_CHECK_INTERVAL = "24h"
        }

        $process = Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -LogPath $logPath -WorkingDir $benchWorkDir -NewWindow:$NewWindow
        $pid = $process.Id

        $baseUrl = "http://127.0.0.1:$Port"
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            try {
                $null = Invoke-WebRequest -Uri "$baseUrl/admin/system/status" -UseBasicParsing -TimeoutSec 2
                $ready = $true; break
            } catch { }
        }
        if (-not $ready) {
            Write-Host "  ERROR: AxonHub did not start on port $Port" -ForegroundColor Red
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            throw "AxonHub failed to start"
        }
        Write-Host "  AxonHub started (PID: $pid)" -ForegroundColor DarkGray

        $initFlag = Join-Path $benchWorkDir "initialized.flag"
        if (-not (Test-Path $initFlag)) {
            Write-Host "  Initializing AxonHub system..." -ForegroundColor DarkGray

            try {
                $status = Invoke-RestMethod -Uri "$baseUrl/admin/system/status" -UseBasicParsing -TimeoutSec 5
                if (-not $status.isInitialized) {
                    $initBody = @{
                        ownerEmail    = "bench@axonhub.local"
                        ownerPassword = "benchbench123"
                        ownerFirstName = "Bench"
                        ownerLastName  = "User"
                        brandName     = "AxonHub Bench"
                    } | ConvertTo-Json
                    $null = Invoke-RestMethod -Uri "$baseUrl/admin/system/initialize" -Method Post -Body $initBody -ContentType "application/json" -UseBasicParsing -TimeoutSec 30
                    Start-Sleep -Seconds 2
                    Write-Host "  System initialized" -ForegroundColor DarkGray
                }

                Write-Host "  Signing in..." -ForegroundColor DarkGray
                try {
                    $loginBody = @{
                        email    = "bench@axonhub.local"
                        password = "benchbench123"
                    } | ConvertTo-Json
                    $loginResp = Invoke-RestMethod -Uri "$baseUrl/admin/auth/signin" -Method Post -Body $loginBody -ContentType "application/json" -UseBasicParsing -TimeoutSec 10
                    $jwtToken = $loginResp.token
                    $authHeader = @{ Authorization = "Bearer $jwtToken" }
                    Write-Host "  JWT token acquired" -ForegroundColor DarkGray

                    $mockPort = ($MockUrl -split ':')[-1]

                    Write-Host "  Creating channel to mock server (port $mockPort)..." -ForegroundColor DarkGray
                    $channelQuery = @"
mutation { createChannel(input: {type: openai, baseURL: "http://127.0.0.1:$mockPort", name: "Mock Server", credentials: {apiKey: "sk-mock-key"}, supportedModels: ["gpt-4o-mini"], defaultTestModel: "gpt-4o-mini"}) { id name status } }
"@
                    $channelBody = @{ query = $channelQuery } | ConvertTo-Json
                    try {
                        $channelResp = Invoke-RestMethod -Uri "$baseUrl/admin/graphql" -Method Post -Body $channelBody -ContentType "application/json" -Headers $authHeader -UseBasicParsing -TimeoutSec 10
                        $channelId = $channelResp.data.createChannel.id
                        if ($channelId) {
                            Write-Host "  Channel created: $channelId" -ForegroundColor DarkGray
                            $enableQuery = @"
mutation { updateChannelStatus(id: "$channelId", status: enabled) { id name status } }
"@
                            $enableBody = @{ query = $enableQuery } | ConvertTo-Json
                            $null = Invoke-RestMethod -Uri "$baseUrl/admin/graphql" -Method Post -Body $enableBody -ContentType "application/json" -Headers $authHeader -UseBasicParsing -TimeoutSec 10
                            Write-Host "  Channel enabled" -ForegroundColor DarkGray
                        }
                    } catch {
                        Write-Host "  Channel may already exist" -ForegroundColor DarkGray
                    }
                    Start-Sleep -Seconds 1
                } catch {
                    Write-Host "  WARNING: Sign-in or channel creation failed: $($_.Exception.Message)" -ForegroundColor Yellow
                }

                Write-Host "  Disabling background tasks..." -ForegroundColor DarkGray
                try {
                    $disableBody = @{ query = "mutation { updateStoragePolicy(input: {storeRequestBody: false, storeResponseBody: false, storeChunks: false, livePreview: false}) }" } | ConvertTo-Json
                    $null = Invoke-RestMethod -Uri "$baseUrl/admin/graphql" -Method Post -Body $disableBody -ContentType "application/json" -Headers $authHeader -UseBasicParsing -TimeoutSec 10
                    $disableBody2 = @{ query = "mutation { updateSystemChannelSettings(input: {probe: {enabled: false, frequency: ONE_HOUR}, autoSync: {frequency: ONE_DAY}}) }" } | ConvertTo-Json
                    $null = Invoke-RestMethod -Uri "$baseUrl/admin/graphql" -Method Post -Body $disableBody2 -ContentType "application/json" -Headers $authHeader -UseBasicParsing -TimeoutSec 10
                    $disableBody3 = @{ query = "mutation { updateRetryPolicy(input: {enabled: false, maxChannelRetries: 0, maxSingleChannelRetries: 0}) }" } | ConvertTo-Json
                    $null = Invoke-RestMethod -Uri "$baseUrl/admin/graphql" -Method Post -Body $disableBody3 -ContentType "application/json" -Headers $authHeader -UseBasicParsing -TimeoutSec 10
                    $disableBody4 = @{ query = 'mutation { completeOnboarding(input: {dummy: ""}) }' } | ConvertTo-Json
                    $null = Invoke-RestMethod -Uri "$baseUrl/admin/graphql" -Method Post -Body $disableBody4 -ContentType "application/json" -Headers $authHeader -UseBasicParsing -TimeoutSec 10
                } catch { }
                Write-Host "  Background tasks disabled" -ForegroundColor DarkGray

                $null = New-Item -Path $initFlag -ItemType File -Force
                Write-Host "  AxonHub initialization complete" -ForegroundColor Green
            } catch {
                Write-Host "  WARNING: Initialization encountered issues: $($_.Exception.Message)" -ForegroundColor Yellow
                $null = New-Item -Path $initFlag -ItemType File -Force
            }
        } else {
            Write-Host "  Using previously initialized AxonHub" -ForegroundColor DarkGray
        }

        return $process
    }.GetNewClosure()

    FairnessNotes = @(
        "Log level set to fatal, metrics disabled, debug mode off",
        "SQLite storage with memory cache (WAL mode)",
        "AXONHUB_SERVER_API_AUTH_ALLOW_NO_AUTH=true disables API key validation (accepts any key)",
        "System auto-initialized via REST POST /admin/system/initialize",
        "Channel auto-created via GraphQL pointing to mock server",
        "Binary auto-downloaded from github.com/looplj/axonhub/releases/tag/v1.0.0-beta5"
    )
}
