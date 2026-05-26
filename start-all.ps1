$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$frontendPath = Join-Path $root "dali-pfe"

if (-not (Test-Path $frontendPath)) {
    throw "Dossier frontend introuvable: $frontendPath"
}

Write-Host "Demarrage du frontend Flutter sur Chrome..."
$backendPath = Join-Path $root "backend"
if (Test-Path $backendPath) {
    Write-Host "Demarrage backend SQL (Node)..."
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location `"$backendPath`"; npm run dev"
}
Write-Host "Demarrage Flutter..."
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location `"$frontendPath`"; flutter run -d chrome --dart-define=API_PORT=3001"
