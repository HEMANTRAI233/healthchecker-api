Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$serviceName = "HealthChecker"
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $existing) {
    Write-Host "Windows service '$serviceName' not found."
    exit 0
}

if ($existing.Status -ne "Stopped") {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
}

& sc.exe delete $serviceName | Out-Null
Write-Host "Windows service '$serviceName' removed."
