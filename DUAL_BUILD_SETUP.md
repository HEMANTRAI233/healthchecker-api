# Dual Platform Build Pipeline - Implementation Summary

## Overview
You now have a complete dual-platform installer build pipeline that generates both Windows and Linux installers automatically.

## Files Modified/Created

### Modified Files
1. **scripts/build.ps1** - Enhanced with platform targeting
   - Added `-TargetPlatform` parameter (windows|linux|both)
   - Builds Windows GUI executable for IIS/Windows Service
   - Cross-compiles Linux x86_64 binary
   - Creates Linux installer bundle (tar.gz with install scripts)

2. **.github/workflows/release.yml** - Dual job architecture
   - `build-windows`: Runs on Windows runner, generates HealthChecker-Setup.exe
   - `build-linux`: Runs on Ubuntu runner, generates HealthChecker-Linux-Installer.tar.gz
   - Both jobs run in parallel automatically

### Created Files

**Linux Deployment (deployments/linux/):**
- `install.sh` - Installation script for Linux systems
- `uninstall.sh` - Removal script for Linux systems  
- `healthchecker.service` - Systemd service unit file

**Documentation:**
- `INSTALLER_GUIDE.md` - Complete installation & troubleshooting guide for both platforms

---

## How It Works

### Local Development Build
```powershell
# Build both installers
./scripts/build.ps1 -UiVersion "ui-1.0.0" -TargetPlatform both

# Or build individually
./scripts/build.ps1 -UiVersion "ui-1.0.0" -TargetPlatform windows
./scripts/build.ps1 -UiVersion "ui-1.0.0" -TargetPlatform linux
```

### Output Artifacts

**When building Windows only:**
```
build/windows/
  ├── HealthChecker.exe
  ├── config/
  │   └── app.env
  └── logs/

HealthChecker-Setup.exe  (created by Inno Setup)
```

**When building Linux only:**
```
build/linux/
  ├── HealthChecker (binary)
  ├── config/
  │   └── app.env
  └── logs/

HealthChecker-Linux-Installer.tar.gz
  └── HealthChecker/
      ├── bin/HealthChecker
      ├── config/app.env
      ├── scripts/{install,uninstall}.sh
      └── systemd/healthchecker.service
```

**When building both:**
- All of the above artifacts are created
- Runs can be independent (useful for manual/CI builds)

---

## GitHub Actions Pipeline

### Automatic Release Trigger
When a UI release is published, it triggers the backend pipeline via `repository_dispatch`:

```bash
# Example trigger command (in UI repo)
curl -X POST https://api.github.com/repos/YOUR_ORG/healthchecker-api/dispatches \
  -H "Authorization: token YOUR_TOKEN" \
  -d '{
    "event_type": "ui_release",
    "client_payload": {
      "ui_version": "ui-1.0.0"
    }
  }'
```

### Pipeline Flow

```
UI Release Published
      ↓
     fork
    ↙    ↖
[Windows]  [Linux]
   ↓         ↓
  Setup.exe  tar.gz
   ↓         ↓
Artifact   Artifact
  Upload    Upload
```

**build-windows job:**
- Runs on: `windows-latest`
- Downloads UI artifacts
- Builds HealthChecker.exe (Windows GUI)
- Creates Inno Setup installer
- Uploads: `HealthChecker-Windows-Setup-<sha>.exe`
- Duration: ~5-10 minutes

**build-linux job:**
- Runs on: `ubuntu-latest`  
- Downloads UI artifacts
- Cross-compiles HealthChecker (Linux x86_64)
- Creates tar.gz bundle with systemd/scripts
- Uploads: `HealthChecker-Linux-Installer-<sha>.tar.gz`
- Duration: ~5-10 minutes

Both jobs run in **parallel**, so total pipeline time is ~10-15 minutes.

---

## Installation Quick Reference

### Windows
```powershell
# Run the downloaded installer
.\HealthChecker-Setup.exe

# Service starts automatically after install
Get-Service HealthChecker
```

### Linux
```bash
# Extract
tar -xzf HealthChecker-Linux-Installer.tar.gz
cd HealthChecker

# Install (requires sudo)
sudo bash scripts/install.sh

# Check status
sudo systemctl status healthchecker
```

---

## Key Features

✅ **Parallel Building** - Both platforms build simultaneously in CI/CD
✅ **Cross-Platform** - Single PowerShell script handles both Windows and Linux builds
✅ **Flexible Targeting** - Build individual platforms or both at once
✅ **No Platform-Specific Branching** - One unified pipeline for all platforms
✅ **Automatic Artifact Upload** - Separate artifacts for Windows/Linux in GitHub
✅ **Service Integration** - Windows Service + Linux systemd unit included
✅ **Installation Scripts** - Linux includes install/uninstall shell scripts
✅ **Configuration Management** - app.env template included in both installers

---

## Next Steps (Optional)

1. **Test the build locally:**
   ```powershell
   ./scripts/build.ps1 -UiVersion "ui-test" -TargetPlatform both
   ```

2. **Test Linux installer bundle:**
   ```bash
   tar -tzf HealthChecker-Linux-Installer.tar.gz | head -20
   ```

3. **Trigger a test release:**
   - Publish a test UI release in the healthchecker-ui repo
   - Monitor the backend pipeline in GitHub Actions
   - Download artifacts from both jobs

4. **Update documentation:**
   - Share [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md) with your deployment team
   - Add troubleshooting for your specific infrastructure

---

## Support

For issues or questions:
- Check [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md) troubleshooting section
- Review GitHub Actions logs for build failures
- Verify database connectivity before installation
