#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

echo "=== Fast-path PID file ==="
if [[ -f "$VMOONGEN_FASTPATH_PID" ]]; then
  cat "$VMOONGEN_FASTPATH_PID"
else
  echo "No fast-path pid file"
fi

echo
echo "=== MoonGen processes ==="
pgrep -af "$MOONGEN_BIN" || echo "No MoonGen process"

echo
echo "=== DPDK runtime files ==="
ls -l /var/run/dpdk/rte/config /var/run/dpdk/rte/mp_socket 2>/dev/null || echo "No DPDK runtime lock files"

echo
echo "=== MoonGen dependency check ==="
"$ROOT/scripts/check-moongen-deps.sh" 2>/dev/null || echo "Dependency check failed"

echo
echo "=== Fast-path readiness ==="
"$ROOT/scripts/check-fastpath-ready.sh" 2>/dev/null || echo "Fast-path host prerequisites not ready"

echo
echo "=== Recent fast-path log ==="
tail -n 20 "$ROOT/logs/fast-path-runtime.log" 2>/dev/null || echo "No fast-path log yet"
