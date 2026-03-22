#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
mkdir -p "$LOGDIR"

log() {
  echo "[$(date '+%F %T')] [FP] $*" | tee -a "$LOGDIR/fast-path-actions.log"
}

log "Stopping MoonGen-side workload"
if [[ -f "$VMOONGEN_FASTPATH_PID" ]]; then
  sudo kill "$(cat "$VMOONGEN_FASTPATH_PID")" 2>/dev/null || true
  rm -f "$VMOONGEN_FASTPATH_PID"
fi
sudo pkill -f "$MOONGEN_BIN" || true
sudo rm -f /var/run/dpdk/rte/config || true
sudo rm -f /var/run/dpdk/rte/mp_socket || true
log "Fast-path stopped"
