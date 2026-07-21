param(
    [switch]$Clean,
    [switch]$Run
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path $scriptDir -Parent
$binDir = Join-Path $repoRoot "bin\windows"

Write-Host ""
Write-Host ("=" * 70)
Write-Host "  Aurora Benchmark Build [Windows]"
Write-Host ("=" * 70)
Write-Host "  Repo root: $repoRoot"
Write-Host "  Bin dir:   $binDir"
Write-Host ("=" * 70)
Write-Host ""

New-Item -ItemType Directory -Force -Path $binDir | Out-Null

if ($Clean) {
    Write-Host "Cleaning old binaries..." -ForegroundColor Yellow
    Get-ChildItem -Path $binDir -Filter "*.exe" | Remove-Item -Force
    Write-Host "  Cleaned all *.exe in $binDir" -ForegroundColor Green
    Write-Host ""
}

$mockOut = Join-Path $binDir "mock-server.exe"
Write-Host "[1/3] Building mock server..." -ForegroundColor Cyan
Push-Location (Join-Path $repoRoot "mock-server")
try {
    go build -o $mockOut ./main.go
    if (-not (Test-Path $mockOut)) { throw "Mock server build failed" }
    Write-Host "  -> $mockOut" -ForegroundColor Green
}
finally {
    Pop-Location
}

$cliOut = Join-Path $binDir "aurora-bench-cli.exe"
$cliSrc = Join-Path $repoRoot "tools\benchmark-cli"
Write-Host "[2/3] Building benchmark CLI..." -ForegroundColor Cyan
Push-Location $repoRoot
try {
    go build -o $cliOut $cliSrc
    if (-not (Test-Path $cliOut)) { throw "Benchmark CLI build failed" }
    Write-Host "  -> $cliOut" -ForegroundColor Green
}
finally {
    Pop-Location
}

$auroraOut = Join-Path $binDir "aurora-bench.exe"
$auroraRepo = Join-Path $repoRoot "..\Aurora_Gateway-oss"
$auroraMain = Join-Path $auroraRepo "apps\aurora"
Write-Host "[3/3] Aurora gateway (from OSS repo)..." -ForegroundColor Cyan
if (Test-Path $auroraMain) {
    Push-Location $auroraRepo
    try {
        go build -ldflags="-X 'aurora/internal/version.Version=dev' -X 'aurora/internal/version.Commit=oss' -s -w" -o $auroraOut ./apps/aurora
        if (-not (Test-Path $auroraOut)) { throw "OSS build failed" }
        Write-Host "  -> $auroraOut" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  ERROR: OSS repo not found at $auroraMain" -ForegroundColor Red
    Write-Host "  Build it manually: go build -o $auroraOut ./apps/aurora" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("=" * 70)
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host ("=" * 70)
if (Test-Path $mockOut) { Write-Host "  mock-server.exe:    $((Get-Item $mockOut).Length / 1KB) KB" }
if (Test-Path $cliOut) { Write-Host "  aurora-bench-cli.exe: $((Get-Item $cliOut).Length / 1KB) KB" }
if (Test-Path $auroraOut) { Write-Host "  aurora-bench.exe:   $((Get-Item $auroraOut).Length / 1KB) KB" }
Write-Host ("=" * 70)
Write-Host ""

if ($Run) {
    $runScript = Join-Path $scriptDir "run.ps1"
    Write-Host "Starting benchmark via $runScript..." -ForegroundColor Cyan
    & $runScript
}
