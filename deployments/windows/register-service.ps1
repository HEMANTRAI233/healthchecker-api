Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HealthChecker"
$displayName = "HealthChecker Service"
$installRoot = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $installRoot "HealthChecker.exe"

if (-not (Test-Path $exePath)) {
    throw "HealthChecker executable not found at: $exePath"
}

$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -ne $existing) {
    if ($existing.Status -ne "Stopped") {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    }

    & sc.exe config $serviceName binPath= "\"$exePath\"" start= auto | Out-Null
}
else {
    & sc.exe create $serviceName binPath= "\"$exePath\"" start= auto DisplayName= "\"$displayName\"" | Out-Null
    & sc.exe description $serviceName "HealthChecker backend service" | Out-Null
}

# Restart automatically if the process exits unexpectedly.
& sc.exe failure $serviceName reset= 0 actions= restart/5000/restart/5000/restart/5000 | Out-Null

Start-Service -Name $serviceName
Write-Host "Windows service '$serviceName' is installed and running."
