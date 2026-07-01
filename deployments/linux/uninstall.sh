#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

SERVICE_NAME="healthchecker.service"

echo "Stopping and removing HealthChecker..."

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
  systemctl stop "${SERVICE_NAME}" || true
  systemctl disable "${SERVICE_NAME}" || true
fi

rm -f "/etc/systemd/system/${SERVICE_NAME}"
systemctl daemon-reload

# Remove the versioned releases directory, the current symlink, and any
# legacy flat installation directory.
rm -rf "/opt/healthchecker/releases"
rm -f  "/opt/healthchecker/current"
# Remove base dir only if it is now empty (avoids deleting unrelated files
# if the directory was pre-existing).
rmdir --ignore-fail-on-non-empty "/opt/healthchecker" || true

rm -rf "/etc/healthchecker"

echo "HealthChecker uninstalled."
