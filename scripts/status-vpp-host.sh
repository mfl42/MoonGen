#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo "=== VPP container ==="
podman ps -a --filter "name=$VMOONGEN_VPP_CONTAINER"

echo
echo "=== VPP socket ==="
ls -l "$VPP_SOCKET" 2>/dev/null || echo "No cli.sock"

echo
echo "=== VPP reachability ==="
if vmoongen_have_vppctl; then
  vmoongen_vppctl show version || true
else
  echo "vppctl not found at $VPP_CTL_BIN"
fi
