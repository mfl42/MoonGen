#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

status=0

check_hugepages() {
  local total free
  total="$(awk '/HugePages_Total/ {print $2}' /proc/meminfo)"
  free="$(awk '/HugePages_Free/ {print $2}' /proc/meminfo)"

  echo "=== Hugepages ==="
  echo "HugePages_Total: ${total:-0}"
  echo "HugePages_Free: ${free:-0}"

  if [[ "${total:-0}" -eq 0 ]]; then
    echo "[ERROR] No hugepages configured. Run: scripts/setup-hugepages.sh" >&2
    status=1
  fi
}

check_vfio() {
  echo
  echo "=== VFIO modules ==="
  if lsmod | grep -Eq '^vfio|^vfio_pci|^vfio_pci_core'; then
    lsmod | grep -E '^vfio|^vfio_pci|^vfio_pci_core'
  else
    echo "[WARN] VFIO modules are not listed in lsmod; relying on dpdk-devbind status." >&2
  fi
}

check_dpdk_binding() {
  local dpdk_status drivers_re nic1_re nic2_re
  drivers_re='drv=(vfio-pci|uio_pci_generic|igb_uio)'
  nic1_re="${VMOONGEN_NIC1//./\\.}"
  nic2_re="${VMOONGEN_NIC2//./\\.}"

  echo
  echo "=== DPDK binding ==="

  if [[ ! -x "$DPDK_DEVBIND" ]]; then
    echo "[ERROR] dpdk-devbind helper not found at $DPDK_DEVBIND" >&2
    status=1
    return
  fi

  dpdk_status="$(sudo "$DPDK_DEVBIND" --status 2>/dev/null || true)"
  if [[ -z "$dpdk_status" ]]; then
    echo "[ERROR] Could not read DPDK device status via $DPDK_DEVBIND" >&2
    status=1
    return
  fi

  echo "$dpdk_status"

  if ! grep -Eq "$drivers_re" <<<"$dpdk_status"; then
    echo "[ERROR] No NIC is bound to a DPDK-compatible driver." >&2
    echo "        Run: scripts/dpdk-bind.sh" >&2
    status=1
  fi

  if [[ -n "${VMOONGEN_NIC1:-}" ]] && ! grep -E "^$nic1_re .*${drivers_re}" <<<"$dpdk_status" >/dev/null; then
    echo "[ERROR] Configured NIC $VMOONGEN_NIC1 is not bound to a DPDK driver." >&2
    status=1
  fi

  if [[ -n "${VMOONGEN_NIC2:-}" ]] && ! grep -E "^$nic2_re .*${drivers_re}" <<<"$dpdk_status" >/dev/null; then
    echo "[ERROR] Configured NIC $VMOONGEN_NIC2 is not bound to a DPDK driver." >&2
    status=1
  fi
}

check_vpp_fastpath_support() {
  echo
  "$SCRIPT_DIR/check-vpp-fastpath-support.sh" || status=1
}

check_hugepages
check_vfio
check_dpdk_binding
check_vpp_fastpath_support

echo
if [[ "$status" -eq 0 ]]; then
  echo "Fast-path host prerequisites look OK."
else
  echo "Fast-path host prerequisites are NOT ready." >&2
  echo "Recommended recovery: scripts/setup-host.sh" >&2
fi

exit "$status"
