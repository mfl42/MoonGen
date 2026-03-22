#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
ACTION_LOG="$LOGDIR/control-plane-actions.log"
RUNTIME_LOG="$LOGDIR/control-plane-daemon.log"

mkdir -p "$LOGDIR"

log_action() {
    echo "[$(date '+%F %T')] [CP] $*" | tee -a "$ACTION_LOG"
}

cd "$ROOT"

if [ -S "$BRIDGE_SOCKET" ]; then
    log_action "Removing stale daemon socket $BRIDGE_SOCKET"
    rm -f "$BRIDGE_SOCKET"
fi

log_action "Starting bridge daemon"
nohup env VMOONGEN_BACKEND="${VMOONGEN_BACKEND:-vpp}" python3 "$ROOT/tools/vpp_bridge_daemon.py" --socket "$BRIDGE_SOCKET" >>"$RUNTIME_LOG" 2>&1 &
DAEMON_PID=$!
echo "$DAEMON_PID" > "$VMOONGEN_DAEMON_PID"
sleep 1

if [ -S "$BRIDGE_SOCKET" ]; then
    log_action "Bridge daemon started successfully (pid=$DAEMON_PID)"
else
    log_action "Bridge daemon did not create socket $BRIDGE_SOCKET"
    exit 1
fi
