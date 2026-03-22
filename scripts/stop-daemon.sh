#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
ACTION_LOG="$LOGDIR/control-plane-actions.log"

mkdir -p "$LOGDIR"

log_action() {
    echo "[$(date '+%F %T')] [CP] $*" | tee -a "$ACTION_LOG"
}

log_action "Stopping bridge daemon"
if [[ -f "$VMOONGEN_DAEMON_PID" ]]; then
    kill "$(cat "$VMOONGEN_DAEMON_PID")" 2>/dev/null || true
fi
pkill -f 'vpp_bridge_daemon.py' || true
rm -f "$BRIDGE_SOCKET" || true
rm -f "$VMOONGEN_DAEMON_PID" || true
log_action "Bridge daemon stopped"
