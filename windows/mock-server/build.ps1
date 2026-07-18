param(
    [string]$Output = ""
)

$scriptDir = Split-Path -Parent $PSCommandPath
$binDir = Join-Path (Split-Path -Parent $scriptDir) "bin"
if ($Output -eq "") {
    $Output = Join-Path $binDir "mock-server.exe"
}
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
Push-Location $scriptDir
try {
    go build -o $Output ./main.go
    Write-Host "Mock server built: $Output" -ForegroundColor Green
}
finally {
    Pop-Location
}
