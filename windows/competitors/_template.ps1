# HOW TO ADD A NEW COMPETITOR
# ==========================
# 1. Copy this file to competitors/NAME.ps1
# 2. Fill in the hashtable fields below
# 3. Add your gateway to run.ps1: -Competitors aurora,NAME
#
# Fields:
#   Name                ??" short identifier (used as filename prefix, CLI arg)
#   DisplayName         ??" human-readable name for reports
#   Language            ??" implementation language (Go, Python, TypeScript, etc.)
#   DefaultPort         ??" port the gateway listens on
#   HealthPath          ??" path for health check (e.g. "health")
#   HealthTimeoutSeconds ??" max wait for gateway to become healthy
#   PreflightSuffix     ??" URL prefix (e.g. "v1")
#   PreflightPath       ??" API path for preflight check (e.g. "chat/completions")
#   PreflightModel      ??" model name for preflight request
#   Type                ??" installation type (source, binary, docker, pip, npm)
#   Install             ??" scriptblock: param($BenchDir, $RepoRoot) ??' $ExePath
#   Start               ??" scriptblock: param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [-NewWindow]) ??' $Process
#   FairnessNotes       ??" array of strings explaining benchmark fairness considerations

return @{
    Name                  = "example"
    DisplayName           = "Example Gateway"
    Language              = "Go"
    DefaultPort           = 8090
    HealthPath            = "health"
    HealthTimeoutSeconds  = 30
    PreflightSuffix       = "v1"
    PreflightPath         = "chat/completions"
    PreflightModel        = "gpt-4o-mini"
    Type                  = "binary"

    Install = {
        param($BenchDir, $RepoRoot)
        # How to install/find the gateway binary
        # Return the path to the executable
        $exePath = Join-Path $BenchDir "bin\windows\example-gateway.exe"
        if (-not (Test-Path $exePath)) {
            Write-Host "Installing Example Gateway..." -ForegroundColor Yellow
            # e.g.:
            # npx -y @example/gateway
            # go install example.com/gateway@latest
            # or use docker, pip install, etc.
            throw "Example Gateway not found. Install it first."
        }
        return $exePath
    }.GetNewClosure()

    Start = {
        param($ExePath, $Port, $MockUrl, $ApiKey, $ResultsDir, [switch]$NewWindow)
        # How to start the gateway process
        $envOverrides = @{
            # Environment variables needed by the gateway
            # PORT = [string]$Port
            # API_KEY = $ApiKey
            # UPSTREAM_URL = $MockUrl
        }
        $extraArgs = @(
            # "-port", [string]$Port
            # "--upstream", $MockUrl
        )
        return Start-GatewayProcess -ExePath $ExePath -EnvOverrides $envOverrides -ExtraArgs $extraArgs -NewWindow:$NewWindow
    }.GetNewClosure()

    FairnessNotes = @(
        "Fairness consideration 1",
        "Fairness consideration 2"
    )
}
