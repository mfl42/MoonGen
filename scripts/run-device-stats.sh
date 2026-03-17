#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo
echo "===================================="
echo " MoonGen Device Statistics"
echo "===================================="
echo

sudo "$MOONGEN_BIN" "$ROOT/examples/device-statistics.lua"
