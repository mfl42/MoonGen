#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
mkdir -p "$LOGDIR"

SCRIPT_PATH="${1:-$ROOT/examples/vpp_multithread_control.lua}"
PORT_ARGS="${2:-0}"
FP_LOG="$LOGDIR/fast-path-runtime.log"
FP_PID="$VMOONGEN_FASTPATH_PID"

log() {
  echo "[$(date '+%F %T')] [FP] $*" | tee -a "$LOGDIR/fast-path-actions.log"
}

if vmoongen_have_vppctl; then
log "Checking VPP before MoonGen-side workload start"
  vmoongen_vppctl show version >/dev/null
fi

vmoongen_require_file "$SCRIPT_PATH" "MoonGen script"
if ! vmoongen_have_moongen; then
  echo "[ERROR] MoonGen binary not found at $MOONGEN_BIN" >&2
  exit 1
fi

log "Checking MoonGen runtime dependencies"
if ! "$ROOT/scripts/check-moongen-deps.sh" | tee -a "$LOGDIR/fast-path-actions.log"; then
  log "MoonGen dependency check failed"
  exit 1
fi

log "Checking host prerequisites for the MoonGen-side workload"
if ! "$ROOT/scripts/check-fastpath-ready.sh" | tee -a "$LOGDIR/fast-path-actions.log"; then
  log "MoonGen-side workload prerequisite check failed"
  exit 1
fi

log "Stopping previous MoonGen process if any"
if [[ -f "$FP_PID" ]]; then
  sudo kill "$(cat "$FP_PID")" 2>/dev/null || true
  rm -f "$FP_PID"
fi
sudo pkill -f "$MOONGEN_BIN" || true
sudo rm -f /var/run/dpdk/rte/config || true
sudo rm -f /var/run/dpdk/rte/mp_socket || true

if [[ -f "$FP_LOG" ]]; then
  ARCHIVE_LOG="${FP_LOG}.$(date '+%Y%m%d-%H%M%S').bak"
  mv "$FP_LOG" "$ARCHIVE_LOG"
  log "Archived previous MoonGen-side runtime log to $ARCHIVE_LOG"
fi
touch "$FP_LOG"

log "Starting MoonGen-side workload with nohup"
IFS=' ' read -r -a PORT_ARGV <<< "$PORT_ARGS"
nohup sudo "$MOONGEN_BIN" "$SCRIPT_PATH" "${PORT_ARGV[@]}" >>"$FP_LOG" 2>&1 &
echo $! > "$FP_PID"

sleep 2

if ! kill -0 "$(cat "$FP_PID")" 2>/dev/null; then
  log "MoonGen-side workload exited immediately; showing recent log tail"
  tail -n 40 "$FP_LOG" 2>/dev/null || true
  exit 1
fi

log "MoonGen-side workload started"
