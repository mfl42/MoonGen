#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
mkdir -p "$LOGDIR"

TOOLBOX_ONLY="${VMOONGEN_TOOLBOX_ONLY:-1}"
RUN_HOST_SETUP="${VMOONGEN_RUN_HOST_SETUP:-$([[ "$TOOLBOX_ONLY" == "1" ]] && echo 0 || echo 1)}"
RESET_DPDK="${VMOONGEN_RESET_DPDK:-0}"
BIND_NICS="${VMOONGEN_BIND_NICS:-0}"
START_VPP="${VMOONGEN_START_VPP:-$([[ "$TOOLBOX_ONLY" == "1" ]] && echo 0 || echo 1)}"

log() {
  echo "[$(date '+%F %T')] [LAB] $*" | tee -a "$LOGDIR/lab-actions.log"
}

log "Starting lab"

if [[ "$RUN_HOST_SETUP" == "1" ]]; then
  log "Running host setup"
  "$ROOT/scripts/setup-host.sh"
else
  log "Toolbox mode: host setup handled separately"
fi

if [[ "$RESET_DPDK" == "1" ]]; then
  log "Resetting DPDK runtime"
  "$ROOT/scripts/dpdk-reset.sh"
fi

if [[ "$BIND_NICS" == "1" ]]; then
  log "Binding NICs"
  "$ROOT/scripts/dpdk-bind.sh"
fi

if [[ "$START_VPP" == "1" ]]; then
  log "Starting host-side VPP container"
  "$ROOT/scripts/start-vpp-host.sh"
else
  log "Toolbox mode: expecting host-side VPP to already be running"
fi

if vmoongen_have_vppctl; then
  log "Checking VPP socket"
  vmoongen_vppctl show version | tee -a "$LOGDIR/vpp-start-check.log"
else
  log "Skipping VPP reachability check: vppctl not found at $VPP_CTL_BIN"
fi

log "Starting control-plane daemon"
"$ROOT/scripts/start-daemon.sh"

log "Checking control-plane status"
"$ROOT/scripts/status-controlplane.sh" | tee -a "$LOGDIR/status-cp.log"

log "Lab ready"
echo
echo "Lab ready."
echo "Host-side steps, if not already done:"
echo "  vmoongenctl start-vpp-host"
echo
echo "Next toolbox steps:"
echo "  vmoongenctl check-fp-ready"
echo "  vmoongenctl start-fp"
echo "  vmoongenctl status-cp"
echo "  vmoongenctl status-fp"
