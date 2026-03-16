#!/usr/bin/env bash
set -e

DPDK_BIND="$HOME/Projects/vMoonGen/libmoon/deps/dpdk/usertools/dpdk-devbind.py"

NIC1="0000:02:00.0"
NIC2="0000:02:00.1"

echo "[INFO] Loading VFIO modules"

sudo modprobe vfio
sudo modprobe vfio_iommu_type1
sudo modprobe vfio-pci

echo "[INFO] Binding NICs to vfio-pci"

sudo "$DPDK_BIND" -b vfio-pci $NIC1
sudo "$DPDK_BIND" -b vfio-pci $NIC2

echo
echo "[INFO] Current DPDK device status"
"$DPDK_BIND" --status
