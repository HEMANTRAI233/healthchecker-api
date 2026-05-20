#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

INSTALL_DIR="/opt/healthchecker"
CONFIG_DIR="/etc/healthchecker"
SERVICE_NAME="healthchecker.service"

echo "Installing HealthChecker..."

mkdir -p "${INSTALL_DIR}"
mkdir -p "${CONFIG_DIR}"

install -m 755 "${ROOT_DIR}/bin/HealthChecker" "${INSTALL_DIR}/HealthChecker"
install -m 644 "${ROOT_DIR}/config/app.env" "${CONFIG_DIR}/app.env"
install -m 644 "${ROOT_DIR}/systemd/healthchecker.service" "/etc/systemd/system/${SERVICE_NAME}"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo "HealthChecker installed and started."
echo "Service status:"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
