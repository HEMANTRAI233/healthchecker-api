param(
    [string]$ExePath = "",
    [string]$InstallDir = "C:\Program Files\HealthChecker",
    [string]$ServiceName = "HealthCheckerAPI",
    [string]$AppPort = "8080",
    [string]$DBHost = "localhost",
    [string]$DBPort = "5432",
    [string]$DBUser = "postgres",
    [string]$DBPassword = "postgres",
    [string]$DBName = "healthchecker",
    [string]$DBSSLMode = "disable"
)

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script as Administrator."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = Join-Path $repoRoot "build/healthchecker.exe"
}
if (-not (Test-Path $ExePath)) {
    throw "Executable not found: $ExePath"
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$targetExe = Join-Path $InstallDir "healthchecker.exe"
Copy-Item -Path $ExePath -Destination $targetExe -Force

$envFile = Join-Path $InstallDir ".env"
@"
APP_PORT=$AppPort
GIN_MODE=release
DB_HOST=$DBHost
DB_PORT=$DBPort
DB_USER=$DBUser
DB_PASSWORD=$DBPassword
DB_NAME=$DBName
DB_SSLMODE=$DBSSLMode
"@ | Set-Content -Path $envFile -Encoding UTF8

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Status -ne "Stopped") {
        Stop-Service -Name $ServiceName -Force
    }
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
}

sc.exe create $ServiceName binPath= "`"$targetExe`"" start= auto DisplayName= "HealthChecker API" | Out-Null
sc.exe description $ServiceName "HealthChecker API service (React UI + Go API + PostgreSQL)." | Out-Null
Start-Service -Name $ServiceName

Write-Host "Service installed and started: $ServiceName"
