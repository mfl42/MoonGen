#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/vMoonGen"
LOG_DIR="$ROOT/logs"
ACTION_LOG="$LOG_DIR/fast-path-actions.log"

mkdir -p "$LOG_DIR"

log_action() {
    echo "[$(date '+%F %T')] [FP] $*" >> "$ACTION_LOG"
}

log_action "Status check"

echo "=== MoonGen processes ==="
ps aux | grep '/home/mfl42/Projects/vMoonGen/libmoon/MoonGen' | grep -v grep || true

echo
echo "=== DPDK runtime files ==="
ls -l /var/run/dpdk/rte/config /var/run/dpdk/rte/mp_socket 2>/dev/null || true

echo
echo "=== DPDK NIC binding ==="
"$HOME/Projects/vMoonGen/libmoon/deps/dpdk/usertools/dpdk-devbind.py" --status
