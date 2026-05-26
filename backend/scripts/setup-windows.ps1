# Prérequis : Node.js LTS installé depuis https://nodejs.org (PATH + redémarrage terminal)
$ErrorActionPreference = "Stop"
$backendRoot = Split-Path -Parent $PSScriptRoot
Set-Location $backendRoot

function Find-NodeExe {
    $candidates = @(
        "node",
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe"
    )
    foreach ($c in $candidates) {
        if ($c -eq "node") {
            $cmd = Get-Command node -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
        } elseif (Test-Path $c) {
            return $c
        }
    }
    return $null
}

$nodeExe = Find-NodeExe
if (-not $nodeExe) {
    Write-Host ""
    Write-Host "ERREUR : Node.js introuvable." -ForegroundColor Red
    Write-Host "1. Installez LTS depuis https://nodejs.org"
    Write-Host "2. Cochez 'Add to PATH'"
    Write-Host "3. Fermez et rouvrez PowerShell"
    Write-Host "4. Relancez ce script"
    Write-Host ""
    Write-Host "Ou lisez INSTALL_WINDOWS.md (option Neon sans PostgreSQL local)."
    exit 1
}

$nodeDir = Split-Path -Parent $nodeExe
$npmCmd = Join-Path $nodeDir "npm.cmd"
if (-not (Test-Path $npmCmd)) {
    $npmCmd = "npm"
}

Write-Host "Node : $nodeExe"
& $nodeExe -v

if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "Fichier .env cree depuis .env.example"
        Write-Host "IMPORTANT : editez .env et mettez votre DATABASE_URL Neon avant setup."
    }
}

$envContent = Get-Content ".env" -Raw -ErrorAction SilentlyContinue
if ($envContent -match "ep-xxxx|USER:PASSWORD@") {
    Write-Host ""
    Write-Host "ATTENTION : .env contient encore l'exemple Neon/PostgreSQL." -ForegroundColor Yellow
    Write-Host "Editez .env puis relancez : npm run setup && npm run dev"
    Write-Host ""
    notepad .env
    exit 0
}

Write-Host ""
Write-Host "npm install..."
& $npmCmd install
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "npm run setup (tables + comptes demo)..."
& $npmCmd run setup
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "OK. Demarrez l'API avec : npm run dev" -ForegroundColor Green
Write-Host "Health : http://localhost:3001/api/health"
