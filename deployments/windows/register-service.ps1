Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HealthChecker"
$displayName = "HealthChecker Service"
$installRoot = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $installRoot "HealthChecker.exe"
$serviceLogDir = "C:\ProgramData\HealthChecker"

New-Item -Path $serviceLogDir -ItemType Directory -Force | Out-Null
$registerLogPath = Join-Path $serviceLogDir "register-service.log"
Start-Transcript -Path $registerLogPath -Append | Out-Null

if (-not (Test-Path $exePath)) {
    throw "HealthChecker executable not found at: $exePath"
}

function Invoke-NativeChecked {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    & $FilePath @Arguments | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ') (exit code $LASTEXITCODE)"
    }
}

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

    Invoke-NativeChecked -FilePath $nssmPath -Arguments @("remove", $serviceName, "confirm")
}

Invoke-NativeChecked -FilePath $nssmPath -Arguments @("install", $serviceName, $exePath)
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "DisplayName", $displayName)
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "Description", "HealthChecker backend service")
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "AppDirectory", $installRoot)
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "Start", "SERVICE_AUTO_START")
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "AppStdout", (Join-Path $serviceLogDir "service-stdout.log"))
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "AppStderr", (Join-Path $serviceLogDir "service-stderr.log"))
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "AppRotateFiles", "1")
Invoke-NativeChecked -FilePath $nssmPath -Arguments @("set", $serviceName, "AppRotateOnline", "1")

Start-Service -Name $serviceName

$installedService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

if ($null -eq $installedService) {
    throw "Service '$serviceName' was not found after installation."
}

if ($installedService.Status -ne "Running") {
    throw "Service '$serviceName' is not running after startup. Current status: $($installedService.Status)"
}

Write-Host "Windows service '$serviceName' is installed and running."
Write-Host "Service registration log: $registerLogPath"

Stop-Transcript | Out-Null
