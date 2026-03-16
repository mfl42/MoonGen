#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/vMoonGen"
LOG_DIR="$ROOT/logs"
ACTION_LOG="$LOG_DIR/fast-path-actions.log"
PID_FILE="$LOG_DIR/fast-path.pid"

mkdir -p "$LOG_DIR"

log_action() {
    echo "[$(date '+%F %T')] [FP] $*" | tee -a "$ACTION_LOG"
}

log_action "Stopping MoonGen fast-path"
sudo pkill -f '/home/mfl42/Projects/vMoonGen/libmoon/MoonGen' || true
sudo rm -f /var/run/dpdk/rte/config || true
sudo rm -f /var/run/dpdk/rte/mp_socket || true
rm -f "$PID_FILE" || true
log_action "MoonGen fast-path stopped"
