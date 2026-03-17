#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

NIC1="$VMOONGEN_NIC1"
NIC2="$VMOONGEN_NIC2"

echo "[INFO] Loading VFIO modules"

sudo modprobe vfio
sudo modprobe vfio_iommu_type1
sudo modprobe vfio-pci

echo "[INFO] Releasing kernel ownership of MoonGen test interfaces"
for iface in $VMOONGEN_IFACES
do
    if ip link show "$iface" >/dev/null 2>&1
    then
        sudo ip addr flush dev "$iface" || true
        sudo ip link set dev "$iface" down || true
    fi
done

echo "[INFO] Binding NICs to vfio-pci"

sudo "$DPDK_DEVBIND" -b vfio-pci "$NIC1"
sudo "$DPDK_DEVBIND" -b vfio-pci "$NIC2"

echo
echo "[INFO] Current DPDK device status"
"$DPDK_DEVBIND" --status
