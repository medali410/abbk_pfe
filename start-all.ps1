$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendPath = Join-Path $root "iot-backend"
$frontendPath = Join-Path $root "dali-pfe"

if (-not (Test-Path $backendPath)) {
    throw "Dossier backend introuvable: $backendPath"
}

if (-not (Test-Path $frontendPath)) {
    throw "Dossier frontend introuvable: $frontendPath"
}

Write-Host "Demarrage du backend Node.js..."
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location `"$backendPath`"; npm start"

Write-Host "Demarrage du frontend Flutter sur Chrome..."
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location `"$frontendPath`"; flutter run -d chrome"

Write-Host "Les deux services sont en cours de lancement."
