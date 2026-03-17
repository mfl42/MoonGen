#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo "=== Daemon process ==="
if [[ -f "$VMOONGEN_DAEMON_PID" ]] && kill -0 "$(cat "$VMOONGEN_DAEMON_PID")" 2>/dev/null; then
  ps -p "$(cat "$VMOONGEN_DAEMON_PID")" -f
else
  pgrep -af 'vpp_bridge_daemon.py' || echo "No bridge daemon process"
fi

echo
echo "=== Sockets ==="
ls -l "$BRIDGE_SOCKET" 2>/dev/null || echo "No $BRIDGE_SOCKET"
ls -l "$VPP_SOCKET" 2>/dev/null || echo "No VPP cli.sock"

echo
echo "=== VPP reachability ==="
if vmoongen_have_vppctl; then
  vmoongen_vppctl show version || true
else
  echo "vppctl not found at $VPP_CTL_BIN"
fi
