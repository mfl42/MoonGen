#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

status=0
mode=""
nic1_id="$(vmoongen_pci_device_id "$VMOONGEN_NIC1" 2>/dev/null || printf 'unknown')"
nic2_id="$(vmoongen_pci_device_id "$VMOONGEN_NIC2" 2>/dev/null || printf 'unknown')"
nic1_family="$(vmoongen_vpp_pci_family "$nic1_id")"
nic2_family="$(vmoongen_vpp_pci_family "$nic2_id")"

echo "=== VPP fast-path runtime ==="
echo "VPP install: $VPP_INSTALL_DIR"
echo "Plugin dir: $(vmoongen_vpp_plugin_dir)"
echo "Driver dir: $(vmoongen_vpp_driver_dir)"
if vmoongen_vpp_has_plugin "dpdk_plugin.so"; then
	echo "Classic DPDK plugin: present"
else
	echo "Classic DPDK plugin: missing"
fi

echo
echo "=== DAC NIC mapping ==="
echo "$VMOONGEN_NIC1 -> $nic1_id ($nic1_family)"
echo "$VMOONGEN_NIC2 -> $nic2_id ($nic2_family)"

echo
echo "=== Mode detection ==="
if mode="$(vmoongen_vpp_detect_fastpath_mode 2>/dev/null)"; then
	echo "Resolved mode: $mode"
	case "$mode" in
	classic-dpdk)
		echo "VPP can own the DAC pair through the classic dpdk{} backend."
		;;
	dev-ige | dev-iavf)
		echo "VPP can own the DAC pair through the devices{} framework."
		;;
	cp-only)
		echo "[WARN] cp-only mode disables the dataplane attachment of the DAC pair." >&2
		status=1
		;;
	esac
else
	echo "[ERROR] No supported VPP fast-path mode was detected." >&2
	vmoongen_vpp_fastpath_failure_hint >&2
	status=1
fi

exit "$status"
