#!/usr/bin/env bash

set -e

ROOT="$HOME/Projects/vMoonGen"
VPP="$HOME/Projects/vpp"

LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"

echo
echo "======================================="
echo " Starting vMoonGen / VPP LAB"
echo "======================================="
echo

echo "[1] Host preparation"
"$ROOT/scripts/setup-host.sh"

echo
echo "[2] Resetting DPDK runtime"
"$ROOT/scripts/dpdk-reset.sh"

echo
echo "[3] Starting VPP"

VPP_LOG="$LOGDIR/vpp.log"

LD_LIBRARY_PATH="$VPP/build-root/install-vpp-native/vpp/lib/x86_64-linux-gnu" \
"$VPP/build-root/install-vpp-native/vpp/bin/vpp" \
> "$VPP_LOG" 2>&1 &

sleep 3

echo "VPP started (log: $VPP_LOG)"

echo
echo "[4] Verifying VPP"

LD_LIBRARY_PATH="$VPP/build-root/install-vpp-native/vpp/lib/x86_64-linux-gnu" \
"$VPP/build-root/install-vpp-native/vpp/bin/vppctl" \
-s "$VPP/run/cli.sock" show version

echo
echo "[5] Starting vMoonGen bridge daemon"

DAEMON_LOG="$LOGDIR/vpp-bridge-daemon.log"

VMOONGEN_BACKEND=vpp \
python3 "$ROOT/tools/vpp_bridge_daemon.py" \
--socket /tmp/vmoongen.sock \
> "$DAEMON_LOG" 2>&1 &

sleep 2

echo "Bridge daemon started (log: $DAEMON_LOG)"

echo
echo "[6] Lab status"

"$ROOT/scripts/check-lab.sh"

echo
echo "======================================="
echo " LAB READY"
echo "======================================="
echo
echo "You can now run MoonGen tests."
echo
