#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo "[HOST] Stopping VPP container $VMOONGEN_VPP_CONTAINER"
podman rm -f "$VMOONGEN_VPP_CONTAINER" >/dev/null 2>&1 || true
rm -f "$VPP_SOCKET" || true

echo "[HOST] VPP stopped"
