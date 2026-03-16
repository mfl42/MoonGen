#!/usr/bin/env bash

ROOT="$HOME/Projects/vMoonGen"

echo
echo "======================================="
echo " Stopping vMoonGen / VPP LAB"
echo "======================================="
echo

echo "[1] Stopping MoonGen"

sudo pkill MoonGen 2>/dev/null || true

echo
echo "[2] Stopping vMoonGen bridge daemon"

pkill -f vpp_bridge_daemon.py 2>/dev/null || true

echo
echo "[3] Stopping VPP"

sudo pkill vpp 2>/dev/null || true

sleep 2

echo
echo "[4] Cleaning DPDK runtime files"

sudo rm -rf /var/run/dpdk 2>/dev/null || true
sudo rm -rf /run/user/*/dpdk 2>/dev/null || true

echo
echo "[5] Cleaning hugepages (optional)"

sudo rm -rf /dev/hugepages/* 2>/dev/null || true

echo
echo "[6] Status"

ps aux | grep -E "MoonGen|vpp|vpp_bridge_daemon" | grep -v grep || echo "All processes stopped"

echo
echo "======================================="
echo " LAB STOPPED"
echo "======================================="
