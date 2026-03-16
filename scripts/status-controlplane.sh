#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/vMoonGen"
LOG_DIR="$ROOT/logs"
ACTION_LOG="$LOG_DIR/control-plane-actions.log"
SOCKET="/tmp/vmoongen.sock"
VPP_SOCKET="$HOME/Projects/vpp/run/cli.sock"

mkdir -p "$LOG_DIR"

log_action() {
    echo "[$(date '+%F %T')] [CP] $*" >> "$ACTION_LOG"
}

log_action "Status check"

echo "=== VPP socket ==="
ls -l "$VPP_SOCKET" 2>/dev/null || true

echo
echo "=== Bridge daemon socket ==="
ls -l "$SOCKET" 2>/dev/null || true

echo
echo "=== Bridge daemon processes ==="
ps aux | grep 'tools/vpp_bridge_daemon.py' | grep -v grep || true

echo
echo "=== VPP reachability ==="
LD_LIBRARY_PATH="$HOME/Projects/vpp/build-root/install-vpp-native/vpp/lib/x86_64-linux-gnu" \
"$HOME/Projects/vpp/build-root/install-vpp-native/vpp/bin/vppctl" \
-s "$VPP_SOCKET" show version || true
