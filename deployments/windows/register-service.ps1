Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HealthChecker"
$displayName = "HealthChecker Service"
$installRoot = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $installRoot "HealthChecker.exe"
$serviceLogDir = "C:\ProgramData\HealthChecker"

if (-not (Test-Path $exePath)) {
    throw "HealthChecker executable not found at: $exePath"
}

New-Item -Path $serviceLogDir -ItemType Directory -Force | Out-Null

function Get-NssmPath {
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue

    if ($null -ne $nssm) {
        return $nssm.Source
    }

    return $null
}

function Ensure-Nssm {
    $nssmPath = Get-NssmPath

    if ($null -ne $nssmPath) {
        return $nssmPath
    }

    $choco = Get-Command choco -ErrorAction SilentlyContinue

    if ($null -eq $choco) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    choco install nssm -y --no-progress

    $nssmPath = Get-NssmPath

    if ($null -eq $nssmPath) {
        throw "NSSM installation failed."
    }

    return $nssmPath
}

$nssmPath = Ensure-Nssm

$existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -ne $existing) {
    if ($existing.Status -ne "Stopped") {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    }

    & $nssmPath remove $serviceName confirm | Out-Null
}

& $nssmPath install $serviceName $exePath | Out-Null
& $nssmPath set $serviceName DisplayName $displayName | Out-Null
& $nssmPath set $serviceName Description "HealthChecker backend service" | Out-Null
& $nssmPath set $serviceName AppDirectory $installRoot | Out-Null
& $nssmPath set $serviceName Start SERVICE_AUTO_START | Out-Null
& $nssmPath set $serviceName AppStdout (Join-Path $serviceLogDir "service-stdout.log") | Out-Null
& $nssmPath set $serviceName AppStderr (Join-Path $serviceLogDir "service-stderr.log") | Out-Null
& $nssmPath set $serviceName AppRotateFiles 1 | Out-Null
& $nssmPath set $serviceName AppRotateOnline 1 | Out-Null

Start-Service -Name $serviceName
Write-Host "Windows service '$serviceName' is installed and running."
