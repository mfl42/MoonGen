#!/usr/bin/env bash

ROOT="$HOME/Projects/vMoonGen"

echo
echo "======================================="
echo " DPDK RESET"
echo "======================================="
echo

echo "[1] Killing MoonGen / DPDK processes"

sudo pkill MoonGen 2>/dev/null || true
sudo pkill -f dpdk 2>/dev/null || true

sleep 1

echo
echo "[2] Removing DPDK runtime files"

sudo rm -rf /var/run/dpdk
sudo rm -rf /run/user/*/dpdk

echo
echo "[3] Clearing hugepages"

sudo rm -rf /dev/hugepages/* 2>/dev/null || true

echo
echo "[4] Resetting NIC binding"

"$ROOT/scripts/bind-interfaces.sh"

echo
echo "[5] Current status"

"$ROOT/libmoon/deps/dpdk/usertools/dpdk-devbind.py" --status

echo
echo "======================================="
echo " DPDK reset complete"
echo "======================================="
