Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$serviceName = "HealthChecker"
$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

function Get-NssmPath {
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue

    if ($null -ne $nssm) {
        return $nssm.Source
    }

    return $null
}

if ($null -eq $existing) {
    Write-Host "Windows service '$serviceName' not found."
    exit 0
}

if ($existing.Status -ne "Stopped") {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
}

$nssmPath = Get-NssmPath

if ($null -ne $nssmPath) {
    & $nssmPath remove $serviceName confirm | Out-Null
}
else {
    & sc.exe delete $serviceName | Out-Null
}

Write-Host "Windows service '$serviceName' removed."
