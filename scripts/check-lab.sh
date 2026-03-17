#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

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

if vmoongen_have_vppctl; then
    vmoongen_vppctl show version 2>/dev/null || echo "VPP not reachable"
else
    echo "vppctl not found at $VPP_CTL_BIN"
fi

echo
echo "---- MoonGen binary ----"

if vmoongen_have_moongen; then
    echo "MoonGen OK"
else
    echo "MoonGen missing at $MOONGEN_BIN"
fi

echo
echo "---- Logs directory ----"

ls -lh "$ROOT/logs" 2>/dev/null || echo "logs directory missing"

echo
echo "---- MoonGen runtime dependencies ----"

"$ROOT/scripts/check-moongen-deps.sh" || true

echo
echo "======================================="
echo " Lab check complete"
echo "======================================="
