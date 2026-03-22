#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

"$ROOT/scripts/stop-lab.sh" || true
sleep 1
"$ROOT/scripts/start-lab.sh"
