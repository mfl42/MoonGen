#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="${1:-$HOME/Projects/vMoonGen/examples/vpp_multithread_control.lua}"
PORT_ARGS="${2:-0}"

"$DIR/stop-fastpath.sh"
sleep 1
"$DIR/start-fastpath.sh" "$SCRIPT_PATH" "$PORT_ARGS"
