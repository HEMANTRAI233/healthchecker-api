Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceName = "HealthChecker"
$displayName = "HealthChecker Service"
$installRoot = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $installRoot "HealthChecker.exe"
# Backup of the previous binary left by the installer's [Code] section so that
# it can be restored if the new binary fails to start (binary rollback).
$previousExePath = Join-Path $installRoot "HealthChecker.exe.previous"
$serviceLogDir = "C:\ProgramData\HealthChecker"
# File written by RunMigrations() recording the schema version before upgrade.
# Used during auto-rollback to restore the DB schema to the pre-upgrade state.
$preUpgradeVersionFile = Join-Path $serviceLogDir ".pre_upgrade_schema_version"

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

# ---------------------------------------------------------------------------
# Wait for the service to reach Running state (mirrors the 15-second startup
# health check in install.sh on Linux).
# ---------------------------------------------------------------------------
$startupTimeout = 15
$elapsed = 0
while ($elapsed -lt $startupTimeout) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -ne $svc -and $svc.Status -eq "Running") {
        break
    }
    Start-Sleep -Seconds 1
    $elapsed++
}

$svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($null -eq $svc -or $svc.Status -ne "Running") {
    Write-Host "ERROR: Service failed to start after $startupTimeout seconds." -ForegroundColor Red

    # -----------------------------------------------------------------------
    # Schema rollback: if the new binary ran migrations before crashing,
    # restore the database schema to the pre-upgrade version so that the
    # previous binary can resume without schema drift.
    #
    # RunMigrations() writes the pre-upgrade schema version to
    # $preUpgradeVersionFile before applying any migrations.  We pass that
    # version back to the new binary via --rollback-schema so its embedded
    # down scripts undo the schema changes in the correct order.
    # -----------------------------------------------------------------------
    if (Test-Path $preUpgradeVersionFile) {
        $preUpgradeVersion = (Get-Content $preUpgradeVersionFile -Raw).Trim()
        Write-Host "Rolling back DB schema to pre-upgrade version: $preUpgradeVersion" -ForegroundColor Yellow
        $rollbackOutput = & $exePath --rollback-schema $preUpgradeVersion 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "DB schema rollback succeeded." -ForegroundColor Green
        } else {
            Write-Host "WARNING: DB schema rollback failed -- manual intervention may be required to prevent schema drift." -ForegroundColor Red
            Write-Host "  Rollback output: $rollbackOutput" -ForegroundColor Red
            Write-Host "  Run: `"$exePath`" --rollback-schema $preUpgradeVersion" -ForegroundColor Yellow
        }
        Remove-Item $preUpgradeVersionFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "WARNING: Pre-upgrade schema version file not found at $preUpgradeVersionFile." -ForegroundColor Yellow
        Write-Host "  If migrations ran before the crash, the DB schema may have drifted." -ForegroundColor Yellow
        Write-Host "  Check: Get-Content '$serviceLogDir\service-stdout.log'" -ForegroundColor Yellow
    }

    # -----------------------------------------------------------------------
    # Binary rollback: if the installer backed up the previous binary before
    # overwriting it, restore it so the previous version can resume service.
    # -----------------------------------------------------------------------
    if (Test-Path $previousExePath) {
        Write-Host "Rolling back to previous binary: $previousExePath" -ForegroundColor Yellow
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        try {
            Copy-Item -Path $previousExePath -Destination $exePath -Force -ErrorAction Stop
            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
            $restoredSvc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($null -ne $restoredSvc -and $restoredSvc.Status -eq "Running") {
                Write-Host "Rollback complete. Previous version is running." -ForegroundColor Green
            } else {
                Write-Host "WARNING: Previous binary also failed to start. Manual intervention required." -ForegroundColor Red
            }
        } catch {
            Write-Host "WARNING: Could not restore previous binary: $_" -ForegroundColor Red
            Write-Host "  Manual restoration may be required." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No previous binary available for automatic rollback." -ForegroundColor Yellow
    }

    Write-Host "Check logs at: $serviceLogDir\service-stdout.log" -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    exit 1
}

# ---------------------------------------------------------------------------
# Service is healthy -- clean up the pre-upgrade version file and the backup
# binary; they were only needed during this upgrade window.
# ---------------------------------------------------------------------------
if (Test-Path $preUpgradeVersionFile) {
    Remove-Item $preUpgradeVersionFile -Force -ErrorAction SilentlyContinue
}
if (Test-Path $previousExePath) {
    Remove-Item $previousExePath -Force -ErrorAction SilentlyContinue
}

Write-Host "Windows service '$serviceName' is installed and running."
Write-Host "Service registration log: $registerLogPath"

Stop-Transcript | Out-Null
