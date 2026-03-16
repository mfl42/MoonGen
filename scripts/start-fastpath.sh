#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/vMoonGen"
LOG_DIR="$ROOT/logs"
ACTION_LOG="$LOG_DIR/fast-path-actions.log"
RUNTIME_LOG="$LOG_DIR/fast-path-runtime.log"
PID_FILE="$LOG_DIR/fast-path.pid"
MOONGEN="$ROOT/libmoon/MoonGen"
SCRIPT="${1:-$ROOT/examples/vpp_multithread_control.lua}"
PORT_ARGS="${2:-0}"
VPPCTL="$HOME/Projects/vpp/build-root/install-vpp-native/vpp/bin/vppctl"
VPP_LIB="$HOME/Projects/vpp/build-root/install-vpp-native/vpp/lib/x86_64-linux-gnu"
VPP_SOCKET="$HOME/Projects/vpp/run/cli.sock"

mkdir -p "$LOG_DIR"

log_action() {
    echo "[$(date '+%F %T')] [FP] $*" | tee -a "$ACTION_LOG"
}

log_action "Checking VPP reachability before starting fast-path"
if ! LD_LIBRARY_PATH="$VPP_LIB" "$VPPCTL" -s "$VPP_SOCKET" show version >/dev/null 2>&1; then
    log_action "VPP is not reachable; fast-path start aborted"
    exit 1
fi

log_action "Cleaning previous DPDK runtime state"
sudo pkill -f '/home/mfl42/Projects/vMoonGen/libmoon/MoonGen' || true
sudo rm -f /var/run/dpdk/rte/config || true
sudo rm -f /var/run/dpdk/rte/mp_socket || true

log_action "Starting MoonGen fast-path: script=$SCRIPT args=$PORT_ARGS"
nohup sudo "$MOONGEN" "$SCRIPT" $PORT_ARGS >>"$RUNTIME_LOG" 2>&1 &
FP_PID=$!
echo "$FP_PID" > "$PID_FILE"
sleep 2

if ps -p "$FP_PID" >/dev/null 2>&1; then
    log_action "MoonGen fast-path started (pid=$FP_PID)"
else
    log_action "MoonGen fast-path exited early; inspect $RUNTIME_LOG"
    exit 1
fi
