#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

status=0

check_cmd() {
	local name="$1"
	if command -v "$name" >/dev/null 2>&1; then
		printf '[OK] command available: %s -> %s\n' "$name" "$(command -v "$name")"
	else
		printf '[ERROR] missing command: %s\n' "$name" >&2
		status=1
	fi
}

check_file() {
	local path="$1"
	local label="$2"
	if [[ -f "$path" ]]; then
		printf '[OK] %s: %s\n' "$label" "$path"
	else
		printf '[ERROR] missing %s: %s\n' "$label" "$path" >&2
		status=1
	fi
}

echo "=== VPP build prerequisites ==="
check_cmd python3
check_cmd cmake
check_cmd ninja
check_cmd pkg-config
check_cmd nasm

echo
echo "=== DPDK build/install artifacts ==="
check_file "$VPP_ROOT/build-root/build-vpp-native/external/build-dpdk/lib/librte_eal.a" "DPDK build artifact"
check_file "$VPP_ROOT/build-root/install-vpp-native/external/lib/libdpdk.a" "DPDK installed aggregate archive"
check_file "$VPP_ROOT/build-root/install-vpp-native/external/lib/pkgconfig/libdpdk.pc" "DPDK pkg-config metadata"

echo
echo "=== VPP dataplane plugin ==="
check_file "$(vmoongen_vpp_plugin_dir)/dpdk_plugin.so" "classic DPDK plugin"

if [[ $status -ne 0 ]]; then
	echo
	echo "[INFO] If the build artifact exists but libdpdk.a is missing, the external DPDK install step is incomplete." >&2
	echo "[INFO] On venus as of 2026-03-17, VPP rebuild attempts are blocked earlier by ipsec-mb because nasm is missing." >&2
	echo "[INFO] Keep VMOONGEN_VPP_FASTPATH_MODE=cp-only until libdpdk.a and dpdk_plugin.so are both present." >&2
fi

exit "$status"
