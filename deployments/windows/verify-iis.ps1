Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$markerPath = "C:\inetpub\wwwroot\Healthchecker\healthchecker-iis-configured.txt"
$rootWebConfigPath = "C:\inetpub\wwwroot\web.config"
$folderWebConfigPath = "C:\inetpub\wwwroot\Healthchecker\web.config"
$logPath = "C:\ProgramData\HealthChecker\configure-iis.log"

if (-not (Test-Path $markerPath)) {
    throw "IIS configuration marker not found at $markerPath. Check $logPath"
}

if (-not (Test-Path $rootWebConfigPath)) {
    throw "IIS root web.config not found at $rootWebConfigPath. Check $logPath"
}

if (-not (Test-Path $folderWebConfigPath)) {
    throw "IIS Healthchecker web.config not found at $folderWebConfigPath. Check $logPath"
}

Write-Host "IIS marker file found: $markerPath"
