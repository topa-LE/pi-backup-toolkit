#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

CONFIG_DIR="${BASE}/config/local"
CONFIG_FILE="${CONFIG_DIR}/toolkit.conf"
CONFIG_TEMPLATE="${CONFIG_DIR}/toolkit.conf.example"

echo "=================================================="
echo "             PI BACKUP TOOLKIT"
echo "                 INSTALLER"
echo "=================================================="
echo

echo "[1/4] Checking required commands ..."

REQUIRED_COMMANDS=(
    ssh
    scp
    bash
    awk
    sed
    grep
    find
    sort
    sha256sum
    timeout
)

for CMD in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "ERROR: Required command missing: $CMD"
        exit 1
    fi
    echo "[✓] $CMD"
done

echo
echo "[2/4] Checking repository structure ..."

for PATH_TO_CHECK in \
    bin/backup-host \
    bin/backup-host-core \
    bin/backup-retention \
    bin/restore-host \
    config/hosts \
    lib/raspberry-offline/backup-engine.sh
do
    if [ ! -e "${BASE}/${PATH_TO_CHECK}" ]; then
        echo "ERROR: Required project file missing: $PATH_TO_CHECK"
        exit 1
    fi
    echo "[✓] $PATH_TO_CHECK"
done

echo
echo "[3/4] Checking local configuration ..."

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    if [ ! -f "$CONFIG_TEMPLATE" ]; then
        echo "ERROR: Configuration template missing."
        exit 1
    fi

    cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"
    echo "[✓] Local configuration created."
else
    echo "[✓] Existing local configuration preserved."
fi

echo
echo "[4/4] Installation permissions ..."

chmod u+x \
    "${BASE}/bin/backup-host" \
    "${BASE}/bin/backup-host-core" \
    "${BASE}/bin/backup-retention" \
    "${BASE}/bin/restore-host"

echo "[✓] Executable permissions verified."

echo
echo "=================================================="
echo "           INSTALLATION COMPLETED"
echo "=================================================="
echo
echo "Repository: $BASE"
echo "Configuration: $CONFIG_FILE"
echo
echo "Next: Configure your own SSH private key."
echo "No personal credentials were installed."
echo
