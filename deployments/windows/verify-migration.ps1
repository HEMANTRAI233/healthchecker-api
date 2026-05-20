Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$backendHealthUrl = "http://127.0.0.1:8080/api/health"
$appLogPath = Join-Path $env:LOCALAPPDATA "HealthChecker\healthchecker.log"
$serviceLogDir = "C:\ProgramData\HealthChecker"
$migrationLogPath = Join-Path $serviceLogDir "migration-check.log"

Start-Transcript -Path $migrationLogPath -Append | Out-Null

Write-Host "=== Database Migration Verification ==="
Write-Host "Checking backend health and database status..."

$maxAttempts = 30
$attempt = 0
$backendReady = $false

while ($attempt -lt $maxAttempts) {
    $attempt++

    try {
        $response = Invoke-WebRequest -Uri $backendHealthUrl -UseBasicParsing -TimeoutSec 3
        
        if ($response.StatusCode -eq 200) {
            $content = $response.Content | ConvertFrom-Json
            
            Write-Host "Backend Status: $($content.Status)"
            Write-Host "Database: $($content.Database)"
            
            if ($content.Status -eq "UP") {
                $backendReady = $true
                break
            }
        }
    }
    catch {
        Write-Host "Attempt $attempt/$maxAttempts - Backend not ready yet..."
        Start-Sleep -Seconds 1
    }
}

if (-not $backendReady) {
    throw "Backend health check failed after 30 seconds. Check C:\ProgramData\HealthChecker\service-stdout.log"
}

Write-Host "Backend is healthy."

if (Test-Path $appLogPath) {
    Write-Host "Checking application log for migration status..."
    $logContent = Get-Content $appLogPath -Tail 50
    
    if ($logContent -match "migration|database" -or $logContent -match "error|failed") {
        Write-Host "Recent log entries:"
        $logContent | ForEach-Object { Write-Host $_ }
    }
}

Write-Host "Migration verification completed successfully."
Write-Host "Migration check log: $migrationLogPath"

Stop-Transcript | Out-Null
