#!/usr/bin/env bash
# rollback.sh -- switch the active HealthChecker release to a previous version.
#
# Usage:
#   sudo bash rollback.sh              # interactive: lists releases, prompts
#   sudo bash rollback.sh <version>    # non-interactive: roll back to <version>
#
# Examples:
#   sudo bash rollback.sh
#   sudo bash rollback.sh 20240615120000
#   sudo bash rollback.sh v1.2.3
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

BASE_DIR="/opt/healthchecker"
RELEASES_DIR="${BASE_DIR}/releases"
CURRENT_LINK="${BASE_DIR}/current"
SERVICE_NAME="healthchecker.service"

# ---------------------------------------------------------------------------
# Validate release directory exists
# ---------------------------------------------------------------------------
if [[ ! -d "${RELEASES_DIR}" ]]; then
  echo "ERROR: No releases directory found at ${RELEASES_DIR}." >&2
  echo "Has HealthChecker ever been installed with the versioned installer?" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# List available releases
# ---------------------------------------------------------------------------
mapfile -t RELEASES < <(find "${RELEASES_DIR}" -mindepth 1 -maxdepth 1 -type d | sort -r)

if [[ "${#RELEASES[@]}" -eq 0 ]]; then
  echo "ERROR: No releases found in ${RELEASES_DIR}." >&2
  exit 1
fi

CURRENT_RELEASE=""
if [[ -L "${CURRENT_LINK}" ]]; then
  CURRENT_RELEASE="$(readlink -f "${CURRENT_LINK}" || true)"
fi

echo ""
echo "Available releases (newest first):"
for i in "${!RELEASES[@]}"; do
  LABEL=""
  if [[ "${RELEASES[${i}]}" == "${CURRENT_RELEASE}" ]]; then
    LABEL=" <-- current"
  fi
  echo "  [${i}] $(basename "${RELEASES[${i}]}")${LABEL}"
done
echo ""

# ---------------------------------------------------------------------------
# Determine target: argument or interactive prompt
# ---------------------------------------------------------------------------
TARGET_RELEASE=""

if [[ "${#}" -ge 1 ]]; then
  # Non-interactive: find the release matching the provided version string
  REQUESTED_VERSION="${1}"
  for r in "${RELEASES[@]}"; do
    if [[ "$(basename "${r}")" == "${REQUESTED_VERSION}" ]]; then
      TARGET_RELEASE="${r}"
      break
    fi
  done

  if [[ -z "${TARGET_RELEASE}" ]]; then
    echo "ERROR: Version '${REQUESTED_VERSION}' not found in ${RELEASES_DIR}." >&2
    echo "Available versions:" >&2
    for r in "${RELEASES[@]}"; do
      echo "  $(basename "${r}")" >&2
    done
    exit 1
  fi
else
  # Interactive: prompt for selection
  read -r -p "Enter the index or version name to roll back to: " SELECTION

  # Check if it's a numeric index
  if [[ "${SELECTION}" =~ ^[0-9]+$ ]] && [[ "${SELECTION}" -lt "${#RELEASES[@]}" ]]; then
    TARGET_RELEASE="${RELEASES[${SELECTION}]}"
  else
    # Treat as a version name
    for r in "${RELEASES[@]}"; do
      if [[ "$(basename "${r}")" == "${SELECTION}" ]]; then
        TARGET_RELEASE="${r}"
        break
      fi
    done
  fi

  if [[ -z "${TARGET_RELEASE}" ]]; then
    echo "ERROR: '${SELECTION}' does not match any available release." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Guard: don't roll back to the currently active release
# ---------------------------------------------------------------------------
if [[ "${TARGET_RELEASE}" == "${CURRENT_RELEASE}" ]]; then
  echo "Release '$(basename "${TARGET_RELEASE}")' is already the active release. Nothing to do."
  exit 0
fi

TARGET_VERSION="$(basename "${TARGET_RELEASE}")"
echo "Rolling back to: ${TARGET_VERSION}"

# ---------------------------------------------------------------------------
# Switch the symlink
# ---------------------------------------------------------------------------
ln -sfn "${TARGET_RELEASE}" "${CURRENT_LINK}"
echo "Symlink updated: ${CURRENT_LINK} -> ${TARGET_RELEASE}"

# ---------------------------------------------------------------------------
# Restart service and verify
# ---------------------------------------------------------------------------
echo "Restarting service..."
systemctl restart "${SERVICE_NAME}"

STARTUP_TIMEOUT=15
ELAPSED=0
while [[ "${ELAPSED}" -lt "${STARTUP_TIMEOUT}" ]]; do
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    break
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "ERROR: Service failed to start with release '${TARGET_VERSION}'." >&2
  echo "Check logs with: journalctl -u ${SERVICE_NAME} -n 50" >&2
  exit 1
fi

echo ""
echo "Rollback complete."
echo "  Active release : ${TARGET_RELEASE}"
echo "  Symlink        : ${CURRENT_LINK} -> ${TARGET_RELEASE}"
echo ""
echo "Service status:"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
