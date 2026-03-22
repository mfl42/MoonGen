#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
SCRIPT_PATH="${1:-$ROOT/examples/vpp_multithread_control.lua}"
PORT_ARGS="${2:-0}"

"$ROOT/scripts/stop-fastpath.sh"
sleep 1
"$ROOT/scripts/start-fastpath.sh" "$SCRIPT_PATH" "$PORT_ARGS"
