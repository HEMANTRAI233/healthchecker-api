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

$backendHealthUrl = "http://127.0.0.1:8080/api/health"
$maxAttempts = 20
$success = $false

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri $backendHealthUrl -UseBasicParsing -TimeoutSec 3

        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
            $success = $true
            break
        }
    }
    catch {
        # Service may still be starting; retry.
    }

    Start-Sleep -Seconds 1
}

if (-not $success) {
    throw "HealthChecker backend is not reachable at $backendHealthUrl. Check Windows service status and logs in C:\ProgramData\HealthChecker\service-*.log"
}

Write-Host "Backend health endpoint is reachable: $backendHealthUrl"
