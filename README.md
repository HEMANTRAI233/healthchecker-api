# healthchecker-api

Single-binary backend that serves:
- embedded React UI (`/`)
- health API (`/api/health`)
- PostgreSQL check API (`/api/db-check`)

This repository is the **backend** in a two-repo setup:
- frontend repo: `HEMANTRAI233/healthchecker-ui`
- backend repo: this repo

---

## What is implemented

### 1) One executable serving UI + API
- Frontend `dist.zip` is downloaded from frontend GitHub release.
- Files are extracted into `ui/dist/`.
- Go embeds `ui/dist/` into the binary.
- Runtime serves:
  - `GET /` and SPA routes from embedded files
  - `GET /api/health` (DB-backed health payload)
  - `GET /api/db-check` (same payload, compatibility endpoint)

### 2) PostgreSQL bootstrap + migrations
On app start:
1. Load config (`.env` from current dir and executable dir)
2. Connect to PostgreSQL maintenance DB
3. Auto-create target DB if missing
4. Run embedded SQL migrations (`migrations/*.sql`)
5. Start HTTP server

### 3) Windows service mode (no CMD window required)
- On Windows, app detects if it is running under Service Control Manager.
- If running as a service, it starts/stops using Windows service lifecycle events.
- This removes dependency on an open command prompt.

### 4) IIS reverse-proxy option
- `scripts/configure-iis.ps1` creates an IIS site that reverse-proxies to backend port.
- Use this if you want users to access app via IIS (for example on port 80) while backend listens on 8080.

---

## API payload used by frontend

`GET /api/health` and `GET /api/db-check` return:

```json
{
  "status": "UP",
  "postgres_version": "...",
  "current_time": "..."
}
```

This matches the current frontend expectation (`Welcome! Check my health` + `Check Now` flow).

---

## Build and packaging scripts

## `scripts/download-ui.ps1`
- Reads UI version from:
  1. `-UiVersion` (if provided)
  2. `UI_VERSION` file
  3. fallback: `latest`
- Downloads frontend release asset (`dist.zip`) from GitHub
- Extracts into `ui/dist/`

## `scripts/build.ps1`
- Calls `download-ui.ps1` (so UI version does **not** need to be passed manually)
- Runs:
  - `go test ./...`
  - `go vet ./...`
- Builds Windows executable:
  - `GOOS=windows GOARCH=amd64 CGO_ENABLED=0`
  - linker flags include `-H=windowsgui` for no-console app packaging
- Output: `build/healthchecker.exe`

---

## Windows installation flow

1. Build exe:
```powershell
./scripts/build.ps1
```

2. Install as Windows service (Admin PowerShell):
```powershell
./scripts/install-service.ps1 -ExePath .\build\healthchecker.exe
```

3. (Optional) Configure IIS reverse proxy to backend:
```powershell
./scripts/configure-iis.ps1 -IISPort 80 -BackendPort 8080
```

After this:
- Service runs in background (no CMD dependency)
- App can be reached either:
  - directly on backend port (`http://localhost:8080`)
  - via IIS (`http://localhost:80`) if configured

---

## CI/CD

Workflow: `.github/workflows/build.yml`
- Uses `scripts/build.ps1`
- Produces:
  - `build/healthchecker.exe`
  - `build/windows-install-scripts.zip`
- Uploads artifacts
- Creates backend GitHub release on push to `main`

---

## Environment variables

Defaults are built in (`.env` optional):

```env
APP_PORT=8080
GIN_MODE=release
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=healthchecker
DB_SSLMODE=disable
```
