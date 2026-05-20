# How to Test New Migrations

## Migration Files Created

I've created a new migration `002_add_audit_logs` that adds an audit logging table:

- **UP (apply):** `internal/database/migrations/002_add_audit_logs.up.sql`
  - Creates `audit_logs` table
  - Creates indexes on `created_at` and `event_type`

- **DOWN (rollback):** `internal/database/migrations/002_add_audit_logs.down.sql`
  - Drops indexes
  - Drops `audit_logs` table

---

## Step 1: Rebuild the Application

Migrations are embedded in the executable at build time. You must rebuild to include the new migration:

```powershell
# Navigate to project root
cd "c:\Users\hemantkumar.REALIMAGE\Documents\GitHub\healthchecker-api"

# Run build script
.\scripts\build.ps1
```

This compiles the binary with the new migration included.

---

## Step 2: Run the Migration (Option A - Start Service)

Once you install the new build on Windows, the migration runs automatically:

```powershell
# Option 1: Install new build (automatically runs migrations)
# Run the installer created from your build script

# Option 2: Or restart service if already installed
Restart-Service HealthChecker -Force
```

The service logs migration execution:
```powershell
Get-Content "$env:LOCALAPPDATA\HealthChecker\healthchecker.log" | Select-String -Pattern "MIGRATION|DATABASE"
```

---

## Step 3: Verify Migration in PostgreSQL

### Quick Check - List All Tables

```powershell
# Connect to PostgreSQL and list all tables
psql -h localhost -U postgres -d healthchecker -c "\dt"

# Expected output - should show:
#  public | application_users | table | postgres
#  public | audit_logs        | table | postgres  ← NEW TABLE
```

### Detailed Check - Show Table Structure

```powershell
# Show columns in audit_logs table
psql -h localhost -U postgres -d healthchecker -c "\d audit_logs"

# Expected output:
#                            Table "public.audit_logs"
#    Column    |            Type             | Collation | Nullable |      Default
# ────────────┼─────────────────────────────┼───────────┼──────────┼──────────────
#  id         | integer                     |           | not null | nextval(...)
#  event_type | character varying(100)      |           | not null |
#  description| text                        |           |          |
#  severity   | character varying(50)       |           |          |
#  created_at | timestamp without time zone |           |          | CURRENT_TIMESTAMP
#  created_by | character varying(255)      |           |          |
```

### Check Indexes

```powershell
# List all indexes
psql -h localhost -U postgres -d healthchecker -c "\di"

# Or check specific indexes on audit_logs
psql -h localhost -U postgres -d healthchecker -c "SELECT * FROM pg_indexes WHERE tablename='audit_logs';"

# Expected output - should show:
# - idx_audit_logs_created_at
# - idx_audit_logs_event_type
```

### Check Migration History

```powershell
# View schema_migrations table (tracks which migrations ran)
psql -h localhost -U postgres -d healthchecker -c "SELECT * FROM schema_migrations ORDER BY version;"

# Expected output:
#  version |            dirty
# ─────────┼──────────────────
#        1 | f               ← migration 001 applied
#        2 | f               ← migration 002 applied ← NEW
```

### Insert Test Data

```powershell
# Test the new table by inserting data
psql -h localhost -U postgres -d healthchecker -c "INSERT INTO audit_logs (event_type, description, severity, created_by) VALUES ('TEST', 'Migration verification test', 'INFO', 'admin');"

# Verify insert worked
psql -h localhost -U postgres -d healthchecker -c "SELECT * FROM audit_logs;"
```

---

## Step 4: Verify via Health Endpoint

Once migration is applied and service is running:

```powershell
# Check backend health
$health = Invoke-WebRequest http://127.0.0.1:8080/api/health -UseBasicParsing | ConvertFrom-Json
$health | Format-List

# If Status is "UP" and postgres_version shows → Migration succeeded ✅
```

---

## Common Issues & Fixes

### Issue: Migration Not Running After Build

**Check:**
```powershell
# Verify new migration file is embedded in binary
# The migrations must be in internal/database/migrations/
# before running build.ps1

Get-ChildItem "internal\database\migrations\"
```

**Fix:**
```powershell
# Ensure files exist, then rebuild
.\scripts\build.ps1
```

### Issue: Service Won't Start After Migration

**Check log:**
```powershell
Get-Content "C:\ProgramData\HealthChecker\service-stdout.log" -Tail 50
```

**Common reasons:**
- SQL syntax error in .up.sql file
- Table already exists (use `IF NOT EXISTS`)
- Permission error (postgres user needs permissions)
- Connection string incorrect in app.env

### Issue: Can't Connect to PostgreSQL

```powershell
# Test PostgreSQL connection
psql -h localhost -U postgres -c "SELECT 1"

# If fails, check:
# - Is PostgreSQL running?
# - Are credentials correct in C:\Program Files\HealthChecker\config\app.env?
# - Can you connect with same credentials?
```

---

## How to Create More Migrations

Follow this pattern:

### Create UP Migration (increment version number)
```sql
-- 003_add_status_column.up.sql
ALTER TABLE application_users ADD COLUMN status VARCHAR(50) DEFAULT 'ACTIVE';
```

### Create DOWN Migration (reverses changes)
```sql
-- 003_add_status_column.down.sql
ALTER TABLE application_users DROP COLUMN status;
```

**File naming:**
- Format: `NNN_description.up.sql` and `NNN_description.down.sql`
- NNN = 001, 002, 003, ... (always 3 digits, incrementing)
- description = lowercase, underscores (no spaces or special chars)
- Location: `internal/database/migrations/`

**Rules:**
- Always use `IF EXISTS` / `IF NOT EXISTS` for idempotency
- Always have a matching .down.sql file
- Test both UP and DOWN migrations
- Keep migrations small and focused (one logical change per migration)

---

## Quick Reference Commands

```powershell
# View all tables
psql -h localhost -U postgres -d healthchecker -c "\dt"

# View table structure
psql -h localhost -U postgres -d healthchecker -c "\d table_name"

# View migration history
psql -h localhost -U postgres -d healthchecker -c "SELECT * FROM schema_migrations;"

# View all indexes
psql -h localhost -U postgres -d healthchecker -c "\di"

# Connect to database interactively
psql -h localhost -U postgres -d healthchecker

# Check service logs
Get-Content "$env:LOCALAPPDATA\HealthChecker\healthchecker.log" -Tail 50
Get-Content "C:\ProgramData\HealthChecker\service-stdout.log" -Tail 50
```

---

## Summary

1. ✅ Created migration files `002_add_audit_logs.up.sql` and `.down.sql`
2. 📦 Rebuild the app to embed the migration: `.\scripts\build.ps1`
3. 🚀 Install/restart to run migration automatically
4. 🔍 Verify with PostgreSQL commands above
5. ✨ Table `audit_logs` will be created in database if migration succeeds
