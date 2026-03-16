#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/vMoonGen"
LOG_DIR="$ROOT/logs"
ACTION_LOG="$LOG_DIR/control-plane-actions.log"
RUNTIME_LOG="$LOG_DIR/control-plane-daemon.log"
SOCKET="/tmp/vmoongen.sock"

mkdir -p "$LOG_DIR"

log_action() {
    echo "[$(date '+%F %T')] [CP] $*" | tee -a "$ACTION_LOG"
}

cd "$ROOT"

if [ -S "$SOCKET" ]; then
    log_action "Removing stale daemon socket $SOCKET"
    rm -f "$SOCKET"
fi

log_action "Starting bridge daemon"
nohup env VMOONGEN_BACKEND=vpp python3 tools/vpp_bridge_daemon.py --socket "$SOCKET" >>"$RUNTIME_LOG" 2>&1 &
DAEMON_PID=$!
echo "$DAEMON_PID" > "$LOG_DIR/control-plane-daemon.pid"
sleep 1

if [ -S "$SOCKET" ]; then
    log_action "Bridge daemon started successfully (pid=$DAEMON_PID)"
else
    log_action "Bridge daemon did not create socket $SOCKET"
    exit 1
fi
