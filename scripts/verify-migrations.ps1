# PowerShell script to verify migrations have been applied to PostgreSQL

param(
    [string]$DBHost = "localhost",
    [string]$DBPort = "5432",
    [string]$DBUser = "postgres",
    [string]$DBPassword = "postgres123",
    [string]$DBName = "healthchecker"
)

$ErrorActionPreference = "Stop"

Write-Host "=== PostgreSQL Migration Verification ===" -ForegroundColor Green
Write-Host "Database: $DBHost`:$DBPort/$DBName"
Write-Host ""

# Check if psql is available
$psqlPath = "psql"
try {
    & $psqlPath --version | Out-Null
}
catch {
    Write-Host "ERROR: psql not found in PATH" -ForegroundColor Red
    Write-Host "Install PostgreSQL client tools or add to PATH"
    exit 1
}

# Set connection environment variables
$env:PGPASSWORD = $DBPassword

Write-Host "Connected to PostgreSQL..."
Write-Host ""

# 1. Check if schema_migrations table exists
Write-Host "1. Checking migration history..." -ForegroundColor Cyan
$migrations = & $psqlPath -h $DBHost -p $DBPort -U $DBUser -d $DBName -t -c "SELECT version, dirty FROM schema_migrations ORDER BY version;" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Could not query migrations" -ForegroundColor Red
    Write-Host $migrations
    exit 1
}

if ([string]::IsNullOrWhiteSpace($migrations)) {
    Write-Host "  No migrations found (empty table)" -ForegroundColor Yellow
}
else {
    $migrations | ForEach-Object {
        if ($_ -match "^\s*(\d+)\s*\|\s*(.+)") {
            $version = $matches[1]
            $dirty = $matches[2].Trim()
            $status = if ($dirty -eq "f") { "✓ Clean" } else { "⚠ Dirty" }
            Write-Host "  Migration $version : $status" -ForegroundColor Green
        }
    }
}

Write-Host ""

# 2. List all tables
Write-Host "2. Checking tables..." -ForegroundColor Cyan
$tables = & $psqlPath -h $DBHost -p $DBPort -U $DBUser -d $DBName -t -c "\dt" 2>&1

$expectedTables = @("application_users", "audit_logs")
$foundTables = @()

$tables | ForEach-Object {
    if ($_ -match "public\s+\|\s+(\w+)\s+\|") {
        $tableName = $matches[1]
        $foundTables += $tableName
        
        $isExpected = $expectedTables -contains $tableName
        $symbol = if ($isExpected) { "✓" } else { "○" }
        Write-Host "  $symbol $tableName" -ForegroundColor Green
    }
}

# Check for missing tables
$expectedTables | ForEach-Object {
    if ($_ -notin $foundTables) {
        Write-Host "  ✗ $_ (MISSING)" -ForegroundColor Red
    }
}

Write-Host ""

# 3. Show structure of audit_logs if it exists
if ("audit_logs" -in $foundTables) {
    Write-Host "3. audit_logs table structure..." -ForegroundColor Cyan
    $structure = & $psqlPath -h $DBHost -p $DBPort -U $DBUser -d $DBName -c "\d audit_logs" 2>&1
    $structure | ForEach-Object {
        if ($_ -match "Column|Indexes") {
            Write-Host ""
            Write-Host "  $_" -ForegroundColor Yellow
        }
        elseif ($_ -match "^\s+\|") {
            Write-Host "  $_"
        }
    }
    Write-Host ""
}

# 4. Check indexes
Write-Host "4. Checking indexes..." -ForegroundColor Cyan
$indexes = & $psqlPath -h $DBHost -p $DBPort -U $DBUser -d $DBName -t -c "SELECT indexname FROM pg_indexes WHERE tablename='audit_logs' ORDER BY indexname;" 2>&1

if ([string]::IsNullOrWhiteSpace($indexes)) {
    Write-Host "  No indexes found on audit_logs" -ForegroundColor Yellow
}
else {
    $indexes | ForEach-Object {
        if ($_ -match "^\s*(\w+)") {
            Write-Host "  ✓ $($matches[1])" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "=== Verification Complete ===" -ForegroundColor Green

# Cleanup
$env:PGPASSWORD = ""
