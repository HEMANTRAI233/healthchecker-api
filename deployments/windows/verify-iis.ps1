Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$appCmd = Join-Path $env:WinDir "System32\inetsrv\appcmd.exe"

if (-not (Test-Path $appCmd)) {
    throw "IIS appcmd not found."
}

Import-Module WebAdministration
$website = Get-Website -Name "Default Web Site" -ErrorAction Stop
$siteRootRaw = $website.physicalPath

if ([string]::IsNullOrWhiteSpace($siteRootRaw)) {
    throw "Default Web Site physical path is empty."
}

$siteRoot = [Environment]::ExpandEnvironmentVariables($siteRootRaw)

$markerPath = Join-Path $siteRoot "Healthchecker\healthchecker-iis-configured.txt"
$rootWebConfigPath = Join-Path $siteRoot "web.config"
$folderWebConfigPath = Join-Path $siteRoot "Healthchecker\web.config"
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
