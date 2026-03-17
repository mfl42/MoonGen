#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo "[STEP 1] Setup hugepages"
sudo "$ROOT/scripts/setup-hugepages.sh"

echo "[STEP 2] Bind interfaces"
sudo "$ROOT/scripts/bind-interfaces.sh"

echo "[STEP 3] Show DPDK status"
"$DPDK_DEVBIND" --status

echo "[STEP 4] Validate fast-path readiness"
"$ROOT/scripts/check-fastpath-ready.sh"

echo "[OK] Host ready"
