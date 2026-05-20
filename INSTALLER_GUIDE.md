# HealthChecker Multi-Platform Installer

This project builds and distributes installers for both Windows and Linux platforms.

## Build Process

### Local Development

Build both installers:
```powershell
./scripts/build.ps1 -UiVersion "ui-1.0.0" -TargetPlatform both
```

Build Windows only:
```powershell
./scripts/build.ps1 -UiVersion "ui-1.0.0" -TargetPlatform windows
```

Build Linux only:
```powershell
./scripts/build.ps1 -UiVersion "ui-1.0.0" -TargetPlatform linux
```

### Artifacts Generated

**Windows:**
- `HealthChecker-Setup.exe` - Inno Setup installer with IIS configuration, Windows service registration, and web UI integration

**Linux:**
- `HealthChecker-Linux-Installer.tar.gz` (or `.zip` fallback) - Contains:
  - `HealthChecker` binary
  - `app.env` configuration file
  - `install.sh` installation script
  - `uninstall.sh` uninstallation script
  - `healthchecker.service` systemd unit file

---

## Windows Installation

### Requirements
- Windows 7 or later (x64)
- Administrator privileges
- IIS (Windows Feature) with URL Rewrite and Application Request Routing extensions
- PostgreSQL database

### Installation Steps

1. Download `HealthChecker-Setup.exe`
2. Right-click and select "Run as administrator"
3. Follow the Inno Setup wizard:
   - Accept the license
   - Choose installation directory (default: `C:\Program Files\HealthChecker`)
   - Select start menu folder
   - Click "Install"

### Post-Installation

- The installer automatically:
  - Registers a Windows Service named `HealthChecker`
  - Configures IIS with reverse proxy routing to localhost:8080
  - Runs database migrations
  - Opens the web UI in your default browser

### Uninstallation

Control Panel → Programs and Features → Select "HealthChecker" → Uninstall

Or manually:
```powershell
# Stop and unregister the Windows service
Get-Service HealthChecker | Stop-Service
& "C:\Program Files\HealthChecker\scripts\unregister-service.ps1"

# Delete the installation folder
Remove-Item -Path "C:\Program Files\HealthChecker" -Recurse -Force
```

### Service Management

```powershell
# Check service status
Get-Service HealthChecker

# Start the service
Start-Service HealthChecker

# Stop the service
Stop-Service HealthChecker

# View service logs
Get-Content "C:\ProgramData\HealthChecker\service-stdout.log"
```

---

## Linux Installation

### Requirements
- Ubuntu 18.04 or CentOS 7+ (x86_64)
- `sudo` privileges
- PostgreSQL database
- systemd (for service management)

### Installation Steps

1. Download and extract the Linux installer bundle:
   ```bash
   tar -xzf HealthChecker-Linux-Installer.tar.gz
   # or
   unzip HealthChecker-Linux-Installer.zip
   ```

2. Run the installation script as root:
   ```bash
   cd HealthChecker
   sudo bash scripts/install.sh
   ```

3. Configure the application:
   ```bash
   sudo nano /etc/healthchecker/app.env
   ```
   - Update `DATABASE_URL` with your PostgreSQL connection string
   - Set `APP_PORT` if needed (default: 8080)

4. Start the service:
   ```bash
   sudo systemctl start healthchecker
   sudo systemctl status healthchecker
   ```

5. Access the web UI:
   ```
   http://localhost:8080/HealthChecker
   ```

### Post-Installation

The installation automatically:
- Creates user and system directories
- Sets up a systemd service
- Configures service to auto-start on system boot
- Creates necessary log directories

### Uninstallation

```bash
cd HealthChecker
sudo bash scripts/uninstall.sh
```

This will:
- Stop the HealthChecker service
- Disable it from auto-start
- Remove the service file
- Delete application and config directories

### Service Management

```bash
# Check service status
sudo systemctl status healthchecker

# Start the service
sudo systemctl start healthchecker

# Stop the service
sudo systemctl stop healthchecker

# Enable auto-start
sudo systemctl enable healthchecker

# Disable auto-start
sudo systemctl disable healthchecker

# View logs (live)
sudo journalctl -u healthchecker -f

# View recent logs
sudo journalctl -u healthchecker -n 50
```

---

## Database Configuration

Both installers require a PostgreSQL database.

### Connection String Format
```
postgres://username:password@host:5432/healthchecker_db
```

### Windows Service
- Edit `C:\Program Files\HealthChecker\config\app.env`
- Restart the service: `Restart-Service HealthChecker`

### Linux Service
- Edit `/etc/healthchecker/app.env`
- Restart the service: `sudo systemctl restart healthchecker`

---

## Troubleshooting

### Windows Issues

**Installer fails to run:**
- Run as Administrator
- Ensure IIS is installed: `OptionalFeatures.exe` → Enable "Internet Information Services"

**Service won't start:**
- Check logs: `C:\ProgramData\HealthChecker\service-stdout.log`
- Verify database connectivity: `echo | telnet <db_host> 5432`
- Check port 8080 is available: `netstat -an | find "8080"`

**Web UI not loading:**
- Verify IIS reverse proxy: `iisreset`
- Check firewall rules for port 80/443

### Linux Issues

**Permission denied on install:**
- Use `sudo`: `sudo bash scripts/install.sh`

**Service won't start:**
- Check logs: `sudo journalctl -u healthchecker -n 50`
- Verify database connectivity: `psql -h <db_host> -U <username> -d healthchecker_db`
- Check port 8080 is available: `sudo netstat -tlnp | grep 8080`

**Configuration errors:**
- Edit config: `sudo nano /etc/healthchecker/app.env`
- Reload service: `sudo systemctl restart healthchecker`

---

## GitHub Actions Release Pipeline

The release workflow automatically builds both installers:

1. **build-windows** job (runs on `windows-latest`):
   - Builds Windows executable
   - Creates Inno Setup installer
   - Uploads `HealthChecker-Windows-Setup-<sha>.exe`

2. **build-linux** job (runs on `ubuntu-latest`):
   - Cross-compiles Linux binary
   - Creates installer bundle
   - Uploads `HealthChecker-Linux-Installer-<sha>.tar.gz`

Both jobs run in parallel, producing artifacts independently.

### Automatic UI Tag Creation

To remove manual tagging, configure both repositories as follows.

1. Backend repository (`healthchecker-api`):
    - Workflow added: `.github/workflows/auto-tag-ui-on-backend-push.yml`
    - Trigger: push to `main`
    - Action: creates a new tag in `HEMANTRAI233/healthchecker-ui` on the latest `main` commit.

2. Required backend secret:
    - `UI_REPO_PAT`: Personal Access Token with access to `HEMANTRAI233/healthchecker-ui`.
    - Minimum classic PAT scope: `repo`.
    - Recommended fine-grained PAT permissions: `Contents: Read and write` on `healthchecker-ui`.

3. UI repository (`healthchecker-ui`):
    - Add a workflow that auto-tags on push to `main`.
    - This ensures UI-only pushes also create tags and trigger the existing release chain.

Reference workflow for `healthchecker-ui`:

```yaml
name: Auto Tag On UI Push

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  create-tag:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: Create tag from latest UI commit
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const owner = context.repo.owner;
            const repo = context.repo.repo;
            const branch = (context.ref || '').replace('refs/heads/', '').replace(/\//g, '-');
            const shortSha = (context.sha || '').slice(0, 7);
            const tagName = `auto-ui-${branch}-${shortSha}-${context.runId}`;

            await github.rest.git.createRef({
              owner,
              repo,
              ref: `refs/tags/${tagName}`,
              sha: context.sha,
            });

            core.info(`Created tag ${tagName}`);
```

---

## Quick Start Examples

### Windows Command Line
```powershell
# Build both installers
./scripts/build.ps1 -UiVersion "ui-latest"

# Result: HealthChecker-Setup.exe
#        (Linux bundle files in build/linux-installer/)
```

### Linux Command Line
```bash
# Extract installer
tar -xzf HealthChecker-Linux-Installer.tar.gz

# Install
cd HealthChecker
sudo bash scripts/install.sh

# Verify
sudo systemctl status healthchecker

# Access
curl http://localhost:8080/HealthChecker
```
