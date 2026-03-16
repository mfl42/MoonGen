#!/usr/bin/env bash
set -e

ROOT="$HOME/Projects/vMoonGen"

echo "[STEP 1] Setup hugepages"
sudo "$ROOT/scripts/setup-hugepages.sh"

echo "[STEP 2] Bind interfaces"
sudo "$ROOT/scripts/bind-interfaces.sh"

echo "[STEP 3] Show DPDK status"
"$ROOT/libmoon/deps/dpdk/usertools/dpdk-devbind.py" --status

echo "[OK] Host ready"
