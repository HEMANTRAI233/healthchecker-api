param(
   [Parameter(Mandatory = $true)]
   [string]$UiVersion,

   [ValidateSet("windows", "linux", "both")]
   [string]$TargetPlatform = "both"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "====================================="
Write-Host "HealthChecker Build Pipeline"
Write-Host "====================================="
Write-Host "Target Platform: $TargetPlatform"
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
# CREATE PLATFORM-SPECIFIC DIRECTORIES
# -----------------------------------

if ($TargetPlatform -eq "windows" -or $TargetPlatform -eq "both") {

   Write-Host ""
   Write-Host "Creating Windows directories..."

   New-Item -ItemType Directory -Path "build/windows" | Out-Null
   New-Item -ItemType Directory -Path "build/windows/config" | Out-Null
   New-Item -ItemType Directory -Path "build/windows/logs" | Out-Null
}

if ($TargetPlatform -eq "linux" -or $TargetPlatform -eq "both") {

   Write-Host ""
   Write-Host "Creating Linux directories..."

   New-Item -ItemType Directory -Path "build/linux" | Out-Null
   New-Item -ItemType Directory -Path "build/linux/config" | Out-Null
   New-Item -ItemType Directory -Path "build/linux/logs" | Out-Null
}

# -----------------------------------
# COPY ENV CONFIG
# -----------------------------------

Write-Host ""
Write-Host "Copying environment config..."

Copy-Item `
   "internal/config/app.env" `
   "build/config/app.env"

if ($TargetPlatform -eq "windows" -or $TargetPlatform -eq "both") {

   Copy-Item `
      "internal/config/app.env" `
      "build/windows/config/app.env"
}

if ($TargetPlatform -eq "linux" -or $TargetPlatform -eq "both") {

   Copy-Item `
      "internal/config/app.env" `
      "build/linux/config/app.env"
}

# -----------------------------------
# BUILD WINDOWS GUI EXE
# -----------------------------------

if ($TargetPlatform -eq "windows" -or $TargetPlatform -eq "both") {

   Write-Host ""
   Write-Host "Building Windows executable..."

   go build -ldflags="-H=windowsgui" -o build/HealthChecker.exe .

   Copy-Item `
      "build/HealthChecker.exe" `
      "build/windows/HealthChecker.exe"
}

# -----------------------------------
# BUILD LINUX BINARY
# -----------------------------------

if ($TargetPlatform -eq "linux" -or $TargetPlatform -eq "both") {

   Write-Host ""
   Write-Host "Building Linux executable..."

   $previousGoos = $env:GOOS
   $previousGoarch = $env:GOARCH

   try {

      $env:GOOS = "linux"
      $env:GOARCH = "amd64"

      go build -o build/linux/HealthChecker .
   }
   finally {

      if ($null -eq $previousGoos) {
         Remove-Item Env:GOOS -ErrorAction SilentlyContinue
      }
      else {
         $env:GOOS = $previousGoos
      }

      if ($null -eq $previousGoarch) {
         Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
      }
      else {
         $env:GOARCH = $previousGoarch
      }
   }

   Write-Host ""
   Write-Host "Creating Linux installer bundle..."

   $linuxInstallerRoot = "build/linux-installer"
   $linuxInstallerAppRoot = Join-Path $linuxInstallerRoot "HealthChecker"

   New-Item -ItemType Directory -Path $linuxInstallerAppRoot -Force | Out-Null
   New-Item -ItemType Directory -Path (Join-Path $linuxInstallerAppRoot "bin") -Force | Out-Null
   New-Item -ItemType Directory -Path (Join-Path $linuxInstallerAppRoot "config") -Force | Out-Null
   New-Item -ItemType Directory -Path (Join-Path $linuxInstallerAppRoot "scripts") -Force | Out-Null
   New-Item -ItemType Directory -Path (Join-Path $linuxInstallerAppRoot "systemd") -Force | Out-Null

   Copy-Item `
      "build/linux/HealthChecker" `
      (Join-Path $linuxInstallerAppRoot "bin/HealthChecker") `
      -Force

   Copy-Item `
      "build/linux/config/app.env" `
      (Join-Path $linuxInstallerAppRoot "config/app.env") `
      -Force

   Copy-Item `
      "deployments/linux/install.sh" `
      (Join-Path $linuxInstallerAppRoot "scripts/install.sh") `
      -Force

   Copy-Item `
      "deployments/linux/uninstall.sh" `
      (Join-Path $linuxInstallerAppRoot "scripts/uninstall.sh") `
      -Force

   Copy-Item `
      "deployments/linux/healthchecker.service" `
      (Join-Path $linuxInstallerAppRoot "systemd/healthchecker.service") `
      -Force

   if (Get-Command chmod -ErrorAction SilentlyContinue) {

      chmod +x (Join-Path $linuxInstallerAppRoot "bin/HealthChecker")
      chmod +x (Join-Path $linuxInstallerAppRoot "scripts/install.sh")
      chmod +x (Join-Path $linuxInstallerAppRoot "scripts/uninstall.sh")
   }

   $linuxTarPath = "HealthChecker-Linux-Installer.tar.gz"
   $linuxZipPath = "HealthChecker-Linux-Installer.zip"

   if (Test-Path $linuxTarPath) {
      Remove-Item $linuxTarPath -Force
   }

   if (Test-Path $linuxZipPath) {
      Remove-Item $linuxZipPath -Force
   }

   if (Get-Command tar -ErrorAction SilentlyContinue) {

      tar -czf $linuxTarPath -C $linuxInstallerRoot "HealthChecker"

      Write-Host ""
      Write-Host "Linux installer bundle generated: $linuxTarPath"
   }
   else {

      Compress-Archive `
         -Path (Join-Path $linuxInstallerRoot "HealthChecker") `
         -DestinationPath $linuxZipPath `
         -Force

      Write-Host ""
      Write-Host "Linux installer bundle generated: $linuxZipPath"
   }
}

Write-Host ""
Write-Host "====================================="
Write-Host "BUILD COMPLETE - ARTIFACTS GENERATED"
Write-Host "====================================="

if ($TargetPlatform -eq "windows" -or $TargetPlatform -eq "both") {
   Write-Host ""
   Write-Host "✓ Windows: build/windows/HealthChecker.exe"
}

if ($TargetPlatform -eq "linux" -or $TargetPlatform -eq "both") {
   Write-Host ""
   Write-Host "✓ Linux: HealthChecker-Linux-Installer.tar.gz"
}

Write-Host ""
Write-Host "====================================="