#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo
echo "========================================"
echo " NIC / DPDK / VFIO diagnostic"
echo "========================================"
echo

echo "---- PCI devices (Ethernet) ----"
lspci | grep -i ethernet
echo

echo "---- Kernel interfaces ----"
ip -br link
echo

echo "---- DPDK binding status ----"
sudo "$DPDK_DEVBIND" --status
echo

echo "---- VFIO modules ----"
lsmod | grep vfio || echo "vfio modules not loaded"
echo

echo "---- IOMMU status ----"
sudo dmesg | grep -i -e iommu -e vt-d -e amd-vi | tail -n 5 || true
echo

echo "---- Hugepages ----"
grep Huge /proc/meminfo
echo

echo "---- Link status (Intel X710) ----"

for iface in $VMOONGEN_IFACES
do
    if ip link show "$iface" &> /dev/null
    then
        echo
        echo "Interface: $iface"
        sudo ethtool "$iface" | grep -E "Link detected|Speed"
    fi
done

echo
echo "---- NUMA / CPU ----"
lscpu | grep -E "NUMA|CPU\(s\)"
echo

echo "---- Done ----"
