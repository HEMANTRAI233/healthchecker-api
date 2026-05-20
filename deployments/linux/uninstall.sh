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

rm -rf "/opt/healthchecker"
rm -rf "/etc/healthchecker"

echo "HealthChecker uninstalled."
