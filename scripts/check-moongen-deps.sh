#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

if ! vmoongen_have_moongen; then
	echo "[ERROR] MoonGen binary not found at $MOONGEN_BIN" >&2
	exit 1
fi

if ! command -v ldd >/dev/null 2>&1; then
	echo "[WARN] ldd not available in this environment; skipping MoonGen dependency check"
	exit 0
fi

echo "=== MoonGen runtime dependencies ==="
ldd "$MOONGEN_BIN"

missing="$(ldd "$MOONGEN_BIN" 2>/dev/null | grep 'not found' || true)"
if [[ -n "$missing" ]]; then
	echo
	echo "[ERROR] Missing MoonGen runtime libraries detected:"
	echo "$missing"

	if grep -q 'libatomic\.so\.1' <<<"$missing"; then
		echo "[HINT] Install libatomic1 in the toolbox/container image."
	fi
	if grep -q 'libnuma\.so\.1' <<<"$missing"; then
		echo "[HINT] Install libnuma1 in the toolbox/container image."
	fi

	exit 1
fi

echo
echo "MoonGen runtime dependencies look OK."
