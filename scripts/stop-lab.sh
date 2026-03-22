#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
mkdir -p "$LOGDIR"
STOP_VPP="${VMOONGEN_STOP_VPP:-0}"

log() {
  echo "[$(date '+%F %T')] [LAB] $*" | tee -a "$LOGDIR/lab-actions.log"
}

log "Stopping fast-path"
"$ROOT/scripts/stop-fastpath.sh" || true

log "Stopping control-plane daemon"
"$ROOT/scripts/stop-daemon.sh" || true

if [[ "$STOP_VPP" == "1" ]]; then
  log "Stopping host-side VPP"
  "$ROOT/scripts/stop-vpp-host.sh" || true
else
  log "Leaving host-side VPP running (VMOONGEN_STOP_VPP=$STOP_VPP)"
fi

log "Cleaning DPDK runtime leftovers"
sudo rm -f /var/run/dpdk/rte/config || true
sudo rm -f /var/run/dpdk/rte/mp_socket || true

log "Lab stopped"
