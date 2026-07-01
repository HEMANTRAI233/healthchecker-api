#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BASE_DIR="/opt/healthchecker"
RELEASES_DIR="${BASE_DIR}/releases"
CURRENT_LINK="${BASE_DIR}/current"
CONFIG_DIR="/etc/healthchecker"
SERVICE_NAME="healthchecker.service"
KEEP_RELEASES=3

# ---------------------------------------------------------------------------
# Determine the version being installed.
# The installer bundle is expected to embed a VERSION file at the root of the
# extracted archive (sibling of the HealthChecker directory).  Fall back to a
# timestamp so every install always lands in its own directory.
# ---------------------------------------------------------------------------
VERSION_FILE="${ROOT_DIR}/VERSION"
if [[ -f "${VERSION_FILE}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
else
  VERSION="$(date +%Y%m%d%H%M%S)"
fi

RELEASE_DIR="${RELEASES_DIR}/${VERSION}"

echo "Installing HealthChecker version: ${VERSION}"
echo "Release directory: ${RELEASE_DIR}"

# ---------------------------------------------------------------------------
# Create directory layout
# ---------------------------------------------------------------------------
mkdir -p "${RELEASE_DIR}"
mkdir -p "${CONFIG_DIR}"

# ---------------------------------------------------------------------------
# Copy binary into the versioned release directory
# ---------------------------------------------------------------------------
install -m 755 "${ROOT_DIR}/bin/HealthChecker" "${RELEASE_DIR}/HealthChecker"

# ---------------------------------------------------------------------------
# Copy config only on first install (don't overwrite admin-edited config on
# upgrades).
# ---------------------------------------------------------------------------
if [[ ! -f "${CONFIG_DIR}/app.env" ]]; then
  install -m 640 "${ROOT_DIR}/config/app.env" "${CONFIG_DIR}/app.env"
  echo "Config installed to ${CONFIG_DIR}/app.env"
else
  echo "Config already exists at ${CONFIG_DIR}/app.env -- skipping (manual edits preserved)."
fi

# ---------------------------------------------------------------------------
# Install the systemd service unit (always refresh from the bundle)
# ---------------------------------------------------------------------------
install -m 644 "${ROOT_DIR}/systemd/healthchecker.service" "/etc/systemd/system/${SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

# ---------------------------------------------------------------------------
# Remember the previous 'current' target so we can roll back if the new
# version fails to start.
# ---------------------------------------------------------------------------
PREVIOUS_RELEASE=""
if [[ -L "${CURRENT_LINK}" ]]; then
  PREVIOUS_RELEASE="$(readlink -f "${CURRENT_LINK}" || true)"
fi

# ---------------------------------------------------------------------------
# Point 'current' symlink at the new release
# ---------------------------------------------------------------------------
ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"

# ---------------------------------------------------------------------------
# Start / restart the service and verify it is running
# ---------------------------------------------------------------------------
echo "Starting service..."
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
  echo "ERROR: Service failed to start after ${STARTUP_TIMEOUT}s." >&2

  # -----------------------------------------------------------------
  # Schema rollback: if the new binary ran migrations before crashing,
  # restore the database schema to the pre-upgrade version so that
  # the previous binary can resume without schema drift.
  #
  # RunMigrations() writes the pre-upgrade schema version to
  # PreUpgradeVersionFile before applying any migrations.  We pass
  # that version back to the new binary via --rollback-schema so its
  # embedded down scripts undo the schema changes in the correct order.
  # -----------------------------------------------------------------
  PRE_UPGRADE_VERSION_FILE="${BASE_DIR}/.pre_upgrade_schema_version"
  if [[ -f "${PRE_UPGRADE_VERSION_FILE}" ]]; then
    PRE_UPGRADE_VERSION="$(tr -d '[:space:]' < "${PRE_UPGRADE_VERSION_FILE}")"
    echo "Rolling back DB schema to pre-upgrade version: ${PRE_UPGRADE_VERSION}" >&2
    if "${RELEASE_DIR}/HealthChecker" --rollback-schema "${PRE_UPGRADE_VERSION}"; then
      echo "DB schema rollback succeeded." >&2
    else
      echo "WARNING: DB schema rollback failed -- manual intervention may be required to prevent schema drift." >&2
      echo "  Run: ${RELEASE_DIR}/HealthChecker --rollback-schema ${PRE_UPGRADE_VERSION}" >&2
    fi
    rm -f "${PRE_UPGRADE_VERSION_FILE}"
  else
    echo "WARNING: Pre-upgrade schema version file not found at ${PRE_UPGRADE_VERSION_FILE}." >&2
    echo "  If migrations ran before the crash, the DB schema may have drifted." >&2
    echo "  Verify with: journalctl -u ${SERVICE_NAME} -n 100" >&2
  fi

  # -----------------------------------------------------------------
  # Auto-rollback: restore the previous release if one exists
  # -----------------------------------------------------------------
  if [[ -n "${PREVIOUS_RELEASE}" && -d "${PREVIOUS_RELEASE}" ]]; then
    echo "Rolling back to previous release: ${PREVIOUS_RELEASE}" >&2
    ln -sfn "${PREVIOUS_RELEASE}" "${CURRENT_LINK}"
    systemctl restart "${SERVICE_NAME}" || true
    echo "Rollback complete. Current symlink now points to: ${PREVIOUS_RELEASE}" >&2
  else
    echo "No previous release available for automatic rollback." >&2
  fi

  echo "Check logs with: journalctl -u ${SERVICE_NAME} -n 50" >&2
  exit 1
fi

echo "Service is running."

# ---------------------------------------------------------------------------
# Clean up the pre-upgrade schema version file now that the new binary is
# confirmed healthy.  It was only needed for potential rollback.
# ---------------------------------------------------------------------------
PRE_UPGRADE_VERSION_FILE="${BASE_DIR}/.pre_upgrade_schema_version"
if [[ -f "${PRE_UPGRADE_VERSION_FILE}" ]]; then
  rm -f "${PRE_UPGRADE_VERSION_FILE}"
fi

# ---------------------------------------------------------------------------
# Prune old releases -- keep only the most recent KEEP_RELEASES
# ---------------------------------------------------------------------------
if [[ -d "${RELEASES_DIR}" ]]; then
  ACTIVE_RELEASE="$(readlink -f "${CURRENT_LINK}")"
  # List releases sorted by creation time (oldest first)
  mapfile -t ALL_RELEASES < <(find "${RELEASES_DIR}" -mindepth 1 -maxdepth 1 -type d | sort)
  TOTAL="${#ALL_RELEASES[@]}"

  if [[ "${TOTAL}" -gt "${KEEP_RELEASES}" ]]; then
    REMOVE_COUNT=$((TOTAL - KEEP_RELEASES))
    for ((i = 0; i < REMOVE_COUNT; i++)); do
      OLD="${ALL_RELEASES[${i}]}"
      if [[ "${OLD}" != "${ACTIVE_RELEASE}" ]]; then
        echo "Pruning old release: ${OLD}"
        rm -rf "${OLD}"
      fi
    done
  fi
fi

echo ""
echo "HealthChecker ${VERSION} installed successfully."
echo "  Active release : ${RELEASE_DIR}"
echo "  Symlink        : ${CURRENT_LINK} -> ${RELEASE_DIR}"
echo "  Config         : ${CONFIG_DIR}/app.env"
echo ""
echo "Service status:"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
