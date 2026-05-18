param(
   [Parameter(Mandatory = $true)]
   [string]$UiVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "====================================="
Write-Host "HealthChecker Build Pipeline"
Write-Host "====================================="

# -----------------------------------
# CLEAN OLD FRONTEND
# -----------------------------------

if (Test-Path "web/dist") {

   Write-Host ""
   Write-Host "Cleaning old frontend..."

   Remove-Item `
       "web/dist" `
       -Recurse `
       -Force
}

# -----------------------------------
# DOWNLOAD FRONTEND
# -----------------------------------

Write-Host ""
Write-Host "Downloading frontend artifact..."

.\scripts\download-ui.ps1 `
   -UiVersion $UiVersion

# -----------------------------------
# CLEAN OLD BUILD
# -----------------------------------

if (Test-Path "build") {

   Write-Host ""
   Write-Host "Cleaning old build..."

   Remove-Item `
       "build" `
       -Recurse `
       -Force
}

# -----------------------------------
# CREATE RELEASE STRUCTURE
# -----------------------------------

Write-Host ""
Write-Host "Creating release folders..."

New-Item `
   -ItemType Directory `
   -Path "build" | Out-Null

New-Item `
   -ItemType Directory `
   -Path "build/config" | Out-Null

New-Item `
   -ItemType Directory `
   -Path "build/logs" | Out-Null

# -----------------------------------
# COPY ENV CONFIG
# -----------------------------------

Write-Host ""
Write-Host "Copying environment config..."

Copy-Item `
   "internal/config/app.env" `
   "build/config/app.env"

# -----------------------------------
# BUILD WINDOWS GUI EXE
# -----------------------------------

Write-Host ""
Write-Host "Building executable..."

go build `
   -ldflags="-H windowsgui" `
   -o build/HealthChecker.exe

Write-Host ""
Write-Host "====================================="
Write-Host "BUILD SUCCESSFUL"
Write-Host "====================================="