# Database Migration Verification - Implementation Summary

## What's Been Added

### 1. New Verification Script
**File:** `deployments/windows/verify-migration.ps1`
- Runs **after** service starts and IIS is configured
- Waits up to 30 seconds for backend to be healthy
- Calls `http://127.0.0.1:8080/api/health` endpoint
- Checks application log for migration-related messages
- Generates transcript log: `C:\ProgramData\HealthChecker\migration-check.log`

### 2. Installer Integration
**File:** `deployments/windows/installer.iss`
- Added `verify-migration.ps1` to [Files] section
- Added migration verification to [Run] section (runs after IIS config)
- Installation order now:
  1. `register-service.ps1` → Service starts, migrations run
  2. `ensure-iis.ps1` → IIS features enabled
  3. `configure-iis.ps1` → Rewrite rules deployed
  4. `verify-iis.ps1` → IIS configuration verified ✓
  5. **`verify-migration.ps1`** → Migration and DB status verified ✓ **NEW**
  6. Browser opens if all pass

---

## How Migration Verification Works

### During Service Startup (Automatic)
When `register-service.ps1` starts the HealthChecker service:
```
APPLICATION STARTING
ENV LOADED
CONFIG LOADED
POSTGRES CONNECTED
RUNNING MIGRATIONS
MIGRATIONS APPLIED
SERVER STARTING on 127.0.0.1:8080
```

**If migrations fail**, the service exits and logs show the error.

### During Installation (verify-migration.ps1)
1. Waits for `/api/health` endpoint to respond with `Status: "UP"`
2. Checks that health endpoint can successfully query the database
3. Reads recent log entries for migration keywords
4. Logs all findings to: `C:\ProgramData\HealthChecker\migration-check.log`
5. If backend is healthy and returns "UP", migrations succeeded

---

## How to Verify It's Working

### After Installation Completes

```powershell
# Quick manual verification
$health = Invoke-WebRequest http://127.0.0.1:8080/api/health -UseBasicParsing | ConvertFrom-Json
$health.Status  # Should be "UP"
$health.PostgresVersion  # Should show version if DB connected

# Check logs
Get-Content "C:\ProgramData\HealthChecker\migration-check.log"
Get-Content "$env:LOCALAPPDATA\HealthChecker\healthchecker.log" -Tail 20
```

### If Migration Fails

The installer will:
1. Show migration verification failure
2. Leave these logs for debugging:
   - `C:\ProgramData\HealthChecker\service-stdout.log` - App startup messages
   - `C:\ProgramData\HealthChecker\service-stderr.log` - Errors from app
   - `C:\ProgramData\HealthChecker\migration-check.log` - Verification attempt
   - `%LOCALAPPDATA%\HealthChecker\healthchecker.log` - Detailed app logs

---

## What Gets Verified

| Check | Source | Success Indicator |
|-------|--------|-------------------|
| Service exists | Get-Service | Service object found |
| Service running | Get-Service | Status = "Running" |
| Backend responsive | HTTP request | HTTP 200 response |
| Database connected | /api/health | Health endpoint returns 200 |
| Migration applied | Log check | App logs show "MIGRATIONS APPLIED" |

---

## Configuration Files Read During Migration

The app loads configuration from (in order):
1. `{ExePath}/config/app.env` ← This is deployed to `C:\Program Files\HealthChecker\config\app.env`
2. `{ExePath}/internal/config/app.env` ← Fallback in development
3. System environment variables ← Fallback

**Key variables for migration:**
- `DB_HOST` (default: localhost)
- `DB_PORT` (default: 5432)
- `DB_USER` (default: postgres)
- `DB_PASSWORD` (required, must be set in app.env)
- `DB_NAME` (default: healthchecker)
- `DB_SSLMODE` (default: disable)

If any of these is wrong, RunMigrations() will fail with an error message in the log.

---

## Next Steps (Optional)

### If You Want More Detailed Database Checks

You could add to `verify-migration.ps1`:
```powershell
# Query database directly to verify tables exist
$connString = "postgres://postgres:password@localhost:5432/healthchecker?sslmode=disable"
# Use psql or PowerShell driver to check schema
```

This would require PostgreSQL client tools on the Windows machine.

### If You Want Migration Rollback Capability

The `golang-migrate` library supports Down() migrations. You could add:
```powershell
# Pre-upgrade: Back up current schema
# Post-downgrade: Restore from backup
```

This is useful for implementing safe upgrade/downgrade flows.

---

## Summary

✅ Migrations now run automatically on service startup  
✅ Installation waits for migration to complete before opening browser  
✅ Detailed logs track migration success/failure  
✅ Health endpoint confirms database is accessible after migration  
✅ Clear error messages if anything fails  

The system will now visibly verify that the database is ready and migrations have run before completing the installation.
