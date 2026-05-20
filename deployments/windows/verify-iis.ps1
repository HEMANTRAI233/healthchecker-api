Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$markerPath = "C:\inetpub\wwwroot\Healthchecker\healthchecker-iis-configured.txt"
$logPath = "C:\ProgramData\HealthChecker\configure-iis.log"

if (-not (Test-Path $markerPath)) {
    throw "IIS configuration marker not found at $markerPath. Check $logPath"
}

Write-Host "IIS marker file found: $markerPath"
