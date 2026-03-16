#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/vMoonGen"
LOG_DIR="$ROOT/logs"
ACTION_LOG="$LOG_DIR/control-plane-actions.log"
SOCKET="/tmp/vmoongen.sock"
PID_FILE="$LOG_DIR/control-plane-daemon.pid"

mkdir -p "$LOG_DIR"

log_action() {
    echo "[$(date '+%F %T')] [CP] $*" | tee -a "$ACTION_LOG"
}

log_action "Stopping bridge daemon"
pkill -f 'tools/vpp_bridge_daemon.py' || true
rm -f "$SOCKET" || true
rm -f "$PID_FILE" || true
log_action "Bridge daemon stopped"
