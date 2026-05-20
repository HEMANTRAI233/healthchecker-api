# Database Migration Verification Guide

## What Happens During Installation

1. **Service Registration** → Backend starts as Windows service on `127.0.0.1:8080`
2. **IIS Configuration** → IIS proxy rules created for `/Healthchecker` route
3. **Backend Health Check** → Installer waits for backend to become healthy
4. **Migration Verification** → Installer calls `/api/health` endpoint and checks database status
5. **Browser Launch** → Opens `http://localhost/Healthchecker/` if all checks pass

---

## How to Check Migration Status

### During Installation (if it fails)

Check these logs in order:

1. **Service Startup Log** (first 20 seconds)
   ```
   C:\ProgramData\HealthChecker\service-stdout.log
   ```
   Look for: `RunMigrations()` or migration error messages

2. **Application Log** (if service started)
   ```
   %LOCALAPPDATA%\HealthChecker\healthchecker.log
   ```
   Look for: `migration|database|error` keywords

3. **IIS Configuration Log**
   ```
   C:\ProgramData\HealthChecker\configure-iis.log
   ```
   Look for: Service status or health check failures

4. **Migration Verification Log** (if backend started)
   ```
   C:\ProgramData\HealthChecker\migration-check.log
   ```
   Look for: Backend health status and database state

### Manual Check (after installation)

Run these PowerShell commands as Admin:

```powershell
# 1. Check service status
Get-Service HealthChecker | Format-List Status, DisplayName

# 2. Check backend directly
Invoke-WebRequest http://127.0.0.1:8080/api/health -UseBasicParsing | ConvertFrom-Json

# 3. Check via IIS proxy
Invoke-WebRequest http://localhost/Healthchecker/api/health -UseBasicParsing | ConvertFrom-Json

# 4. Check application log for migration errors
Get-Content "$env:LOCALAPPDATA\HealthChecker\healthchecker.log" -Tail 30
```

---

## Expected Output (Healthy)

**Backend Health Endpoint Response:**
```json
{
  "Status": "UP",
  "Database": "connected"
}
```

**Service Log Should Show:**
```
APPLICATION STARTING
ENV LOADED
DATABASE CONNECTED
RUNNING MIGRATIONS
MIGRATION COMPLETED
SERVER STARTING on 127.0.0.1:8080
```

---

## Common Issues & What to Check

| Issue | Check These Logs | Likely Cause |
|-------|-----------------|--------------|
| Service won't start | `service-stdout.log`, `service-stderr.log` | Config missing, DB unreachable, bad executable |
| Health endpoint returns error | `healthchecker.log` | Database connection failed, migration error |
| IIS returns 502 | `verify-iis.ps1` output | Backend not running, port blocked, service crashed |
| Backend starts but migrations fail | `healthchecker.log` | Bad SQL in migration files, DB permissions, connection string |
| Browser shows 404 | `configure-iis.log` | IIS config not applied, marker file missing |

---

## Database Connection Requirements

For migrations to work, backend needs:
- **DB Host**: `localhost` (or configured in `app.env`)
- **DB Port**: `5432`
- **DB User**: `postgres`
- **DB Password**: configured in `app.env` or env var
- **DB Name**: `healthchecker`
- **DB Permissions**: User must have CREATE TABLE, INSERT, SELECT permissions

If any of these is wrong, RunMigrations() will fail and service will exit.

---

## Viewing Raw Migration Files

Migration source is embedded in binary at compile time. To see what migrations are available:
- Check `migrations/` folder in source code (e.g., `001_initial_schema.up.sql`)
- These are compiled into the executable

If new migrations are added to source, you must rebuild the executable for them to be included.
