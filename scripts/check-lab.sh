#!/usr/bin/env bash

ROOT="$HOME/Projects/vMoonGen"
VPP="$HOME/Projects/vpp"

echo
echo "======================================="
echo " vMoonGen / VPP LAB HEALTH CHECK"
echo "======================================="
echo

echo "---- Hugepages ----"
grep Huge /proc/meminfo
echo

echo "---- VFIO modules ----"
lsmod | grep vfio || echo "vfio not loaded"
echo

echo "---- NICs (PCI) ----"
lspci | grep -i ethernet
echo

echo "---- DPDK binding ----"
sudo "$ROOT/libmoon/deps/dpdk/usertools/dpdk-devbind.py" --status
echo

echo "---- Network interfaces ----"
ip -br link
echo

echo "---- VPP CLI check ----"

LD_LIBRARY_PATH="$VPP/build-root/install-vpp-native/vpp/lib/x86_64-linux-gnu" \
"$VPP/build-root/install-vpp-native/vpp/bin/vppctl" \
-s "$VPP/run/cli.sock" show version 2>/dev/null || echo "VPP not reachable"

echo
echo "---- MoonGen binary ----"

if [ -x "$ROOT/libmoon/MoonGen" ]; then
    echo "MoonGen OK"
else
    echo "MoonGen missing"
fi

echo
echo "---- Logs directory ----"

ls -lh "$ROOT/logs" 2>/dev/null || echo "logs directory missing"

echo
echo "======================================="
echo " Lab check complete"
echo "======================================="
