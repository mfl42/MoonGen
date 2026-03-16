#!/usr/bin/env bash

set -e

ROOT="$HOME/Projects/vMoonGen"
DPDK_BIND="$ROOT/libmoon/deps/dpdk/usertools/dpdk-devbind.py"

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
sudo $DPDK_BIND --status
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

for iface in enp2s0f0np0 enp2s0f1np1
do
    if ip link show "$iface" &> /dev/null
    then
        echo
        echo "Interface: $iface"
        sudo ethtool $iface | grep -E "Link detected|Speed"
    fi
done

echo
echo "---- NUMA / CPU ----"
lscpu | grep -E "NUMA|CPU\(s\)"
echo

echo "---- Done ----"
