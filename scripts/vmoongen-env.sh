#!/usr/bin/env bash
# shellcheck shell=bash

if [[ -n "${VMOONGEN_ENV_LOADED:-}" ]]; then
	return 0 2>/dev/null || exit 0
fi
VMOONGEN_ENV_LOADED=1

_vmoongen_source="${BASH_SOURCE[0]}"
while [[ -L "$_vmoongen_source" ]]; do
	_vmoongen_dir="$(cd "$(dirname "$_vmoongen_source")" && pwd)"
	_vmoongen_source="$(readlink "$_vmoongen_source")"
	[[ "$_vmoongen_source" != /* ]] && _vmoongen_source="$_vmoongen_dir/$_vmoongen_source"
done
_vmoongen_script_dir="$(cd "$(dirname "$_vmoongen_source")" && pwd)"

export ROOT="${VMOONGEN_ROOT:-$(cd "$_vmoongen_script_dir/.." && pwd)}"
export VMOONGEN_ROOT="$ROOT"
export LOGDIR="${VMOONGEN_LOG_DIR:-$ROOT/logs}"
export BRIDGE_SOCKET="${VMOONGEN_BRIDGE_SOCKET:-/tmp/vmoongen.sock}"

if [[ -z "${VPP_ROOT:-}" && -n "${VMOONGEN_VPP_ROOT:-}" ]]; then
	export VPP_ROOT="$VMOONGEN_VPP_ROOT"
elif [[ -z "${VPP_ROOT:-}" ]]; then
	for _cand in \
		"$ROOT/../vpp" \
		"$HOME/Projects/vpp" \
		"$HOME/vpp"
	do
		if [[ -d "$_cand" ]]; then
			export VPP_ROOT="$_cand"
			break
		fi
	done
fi

export VPP_ROOT="${VPP_ROOT:-$HOME/Projects/vpp}"
export VPP_RUN_DIR="${VPP_RUN_DIR:-$VPP_ROOT/run}"
export VPP_INSTALL_DIR="${VPP_INSTALL_DIR:-$VPP_ROOT/build-root/install-vpp-native/vpp}"
export VPP_SOCKET="${VPP_SOCKET:-$VPP_RUN_DIR/cli.sock}"
export VPP_CTL_BIN="${VPP_CTL_BIN:-$VPP_INSTALL_DIR/bin/vppctl}"
export VPP_BIN="${VPP_BIN:-$VPP_INSTALL_DIR/bin/vpp}"
export VPP_LIB_DIR="${VPP_LIB_DIR:-$VPP_INSTALL_DIR/lib/x86_64-linux-gnu}"
export VPP_SESSION_CONF="${VPP_SESSION_CONF:-$VPP_RUN_DIR/vpp-session.conf}"
export VMOONGEN_VPP_SESSION="${VMOONGEN_VPP_SESSION:-vpp}"
export VMOONGEN_VPP_CONTAINER="${VMOONGEN_VPP_CONTAINER:-vmoongen-vpp}"
export VMOONGEN_VPP_IMAGE="${VMOONGEN_VPP_IMAGE:-docker.io/library/ubuntu:24.04}"
export VMOONGEN_VPP_WORKDIR="${VMOONGEN_VPP_WORKDIR:-/workspace/vpp}"
export VMOONGEN_VPP_WORKERS="${VMOONGEN_VPP_WORKERS:-2}"
export VMOONGEN_VPP_RX_QUEUES="${VMOONGEN_VPP_RX_QUEUES:-1}"
export VMOONGEN_VPP_TX_QUEUES="${VMOONGEN_VPP_TX_QUEUES:-1}"
export VMOONGEN_VPP_RX_QUEUE_SIZE="${VMOONGEN_VPP_RX_QUEUE_SIZE:-512}"
export VMOONGEN_VPP_TX_QUEUE_SIZE="${VMOONGEN_VPP_TX_QUEUE_SIZE:-512}"
export VMOONGEN_VPP_RENDER_CONFIG="${VMOONGEN_VPP_RENDER_CONFIG:-0}"
export VMOONGEN_VPP_FASTPATH_MODE="${VMOONGEN_VPP_FASTPATH_MODE:-auto}"
export VMOONGEN_VPP_IFACE1_NAME="${VMOONGEN_VPP_IFACE1_NAME:-dac0}"
export VMOONGEN_VPP_IFACE2_NAME="${VMOONGEN_VPP_IFACE2_NAME:-dac1}"
export VMOONGEN_FASTPATH_PID="${VMOONGEN_FASTPATH_PID:-$LOGDIR/fast-path.pid}"
export VMOONGEN_DAEMON_PID="${VMOONGEN_DAEMON_PID:-$LOGDIR/control-plane-daemon.pid}"
export VMOONGEN_IFACES="${VMOONGEN_IFACES:-enp2s0f0np0 enp2s0f1np1}"
export VMOONGEN_NIC1="${VMOONGEN_NIC1:-0000:02:00.0}"
export VMOONGEN_NIC2="${VMOONGEN_NIC2:-0000:02:00.1}"
export VMOONGEN_HUGEPAGES="${VMOONGEN_HUGEPAGES:-512}"
export VMOONGEN_HUGEPAGES_MOUNT="${VMOONGEN_HUGEPAGES_MOUNT:-/dev/hugepages}"

if [[ -z "${MOONGEN_BIN:-}" ]]; then
	if [[ -x "$ROOT/libmoon/MoonGen" ]]; then
		MOONGEN_BIN="$ROOT/libmoon/MoonGen"
	elif [[ -x "$ROOT/build/MoonGen" ]]; then
		MOONGEN_BIN="$ROOT/build/MoonGen"
	else
		MOONGEN_BIN="$ROOT/libmoon/MoonGen"
	fi
fi
export MOONGEN_BIN

export DPDK_DEVBIND="${DPDK_DEVBIND:-$ROOT/libmoon/deps/dpdk/usertools/dpdk-devbind.py}"

vmoongen_vpp_plugin_dir() {
	printf '%s\n' "$VPP_INSTALL_DIR/lib/x86_64-linux-gnu/vpp_plugins"
}

vmoongen_vpp_driver_dir() {
	printf '%s\n' "$VPP_INSTALL_DIR/lib/x86_64-linux-gnu/vpp_drivers"
}

vmoongen_vpp_has_plugin() {
	local plugin_name="$1"
	[[ -f "$(vmoongen_vpp_plugin_dir)/$plugin_name" ]]
}

vmoongen_vpp_has_driver() {
	local driver_name="$1"
	[[ -f "$(vmoongen_vpp_driver_dir)/$driver_name" ]]
}

vmoongen_pci_device_id() {
	local pci_addr="$1"
	local device_file="/sys/bus/pci/devices/$pci_addr/device"
	local value

	[[ -r "$device_file" ]] || return 1
	value="$(<"$device_file")"
	value="${value#0x}"
	value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
	printf '0x%s\n' "$value"
}

vmoongen_vpp_pci_family() {
	local device_id="${1#0x}"
	device_id="$(printf '%s' "$device_id" | tr '[:upper:]' '[:lower:]')"

	case "$device_id" in
	1539 | 15f2 | 15f3 | 0d9f | 125b | 125c | 125d) printf 'ige\n' ;;
	1889 | 154c | 37cd) printf 'iavf\n' ;;
	1572 | 1583) printf 'x710-pf\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

vmoongen_vpp_detect_fastpath_mode() {
	local requested_mode="${1:-${VMOONGEN_VPP_FASTPATH_MODE:-auto}}"
	local nic1_id nic2_id nic1_family nic2_family

	nic1_id="$(vmoongen_pci_device_id "$VMOONGEN_NIC1" 2>/dev/null || printf 'unknown')"
	nic2_id="$(vmoongen_pci_device_id "$VMOONGEN_NIC2" 2>/dev/null || printf 'unknown')"
	nic1_family="$(vmoongen_vpp_pci_family "$nic1_id")"
	nic2_family="$(vmoongen_vpp_pci_family "$nic2_id")"

	case "$requested_mode" in
	auto) ;;
	cp-only)
		printf 'cp-only\n'
		return 0
		;;
	classic-dpdk)
		vmoongen_vpp_has_plugin "dpdk_plugin.so" || return 1
		printf 'classic-dpdk\n'
		return 0
		;;
	dev-ige)
		[[ "$nic1_family" == "ige" && "$nic2_family" == "ige" ]] || return 1
		vmoongen_vpp_has_driver "ige_driver.so" || return 1
		printf 'dev-ige\n'
		return 0
		;;
	dev-iavf)
		[[ "$nic1_family" == "iavf" && "$nic2_family" == "iavf" ]] || return 1
		vmoongen_vpp_has_driver "iavf_driver.so" || return 1
		printf 'dev-iavf\n'
		return 0
		;;
	*)
		return 1
		;;
	esac

	if vmoongen_vpp_has_plugin "dpdk_plugin.so"; then
		printf 'classic-dpdk\n'
		return 0
	fi

	if [[ "$nic1_family" == "ige" && "$nic2_family" == "ige" ]] && vmoongen_vpp_has_driver "ige_driver.so"; then
		printf 'dev-ige\n'
		return 0
	fi

	if [[ "$nic1_family" == "iavf" && "$nic2_family" == "iavf" ]] && vmoongen_vpp_has_driver "iavf_driver.so"; then
		printf 'dev-iavf\n'
		return 0
	fi

	return 1
}

vmoongen_vpp_fastpath_failure_hint() {
	local requested_mode="${1:-${VMOONGEN_VPP_FASTPATH_MODE:-auto}}"
	local nic1_id nic2_id nic1_family nic2_family

	nic1_id="$(vmoongen_pci_device_id "$VMOONGEN_NIC1" 2>/dev/null || printf 'unknown')"
	nic2_id="$(vmoongen_pci_device_id "$VMOONGEN_NIC2" 2>/dev/null || printf 'unknown')"
	nic1_family="$(vmoongen_vpp_pci_family "$nic1_id")"
	nic2_family="$(vmoongen_vpp_pci_family "$nic2_id")"

	if [[ "$nic1_family" == "x710-pf" || "$nic2_family" == "x710-pf" ]] && ! vmoongen_vpp_has_plugin "dpdk_plugin.so"; then
		printf '%s\n' \
			"Installed VPP build at $VPP_INSTALL_DIR does not ship dpdk_plugin.so, and the available new-framework drivers do not support Intel X710/XL710 PF devices ($nic1_id, $nic2_id)." \
			"Rebuild or reinstall VPP with classic DPDK/i40e support before enabling the DAC pair in VPP."
		return 0
	fi

	case "$requested_mode" in
	classic-dpdk)
		printf '%s\n' "Requested classic-dpdk, but $(vmoongen_vpp_plugin_dir)/dpdk_plugin.so is missing."
		;;
	dev-ige)
		printf '%s\n' "Requested dev-ige, but the DAC pair is not backed by IGE-class devices or ige_driver.so is missing."
		;;
	dev-iavf)
		printf '%s\n' "Requested dev-iavf, but the DAC pair is not backed by IAVF-class devices or iavf_driver.so is missing."
		;;
	*)
		printf '%s\n' \
			"No compatible VPP fast-path mode was detected for $VMOONGEN_NIC1 ($nic1_id / $nic1_family) and $VMOONGEN_NIC2 ($nic2_id / $nic2_family)." \
			"Use VMOONGEN_VPP_FASTPATH_MODE=cp-only for control-plane-only bring-up, or install a VPP build that supports the NIC pair in dataplane mode."
		;;
	esac
}

vmoongen_have_vppctl() {
	[[ -x "$VPP_CTL_BIN" ]]
}

vmoongen_have_moongen() {
	[[ -x "$MOONGEN_BIN" ]]
}

vmoongen_require_file() {
	local path="$1"
	local label="$2"
	if [[ ! -e "$path" ]]; then
		echo "[ERROR] Missing ${label}: $path" >&2
		return 1
	fi
}

vmoongen_vppctl() {
	LD_LIBRARY_PATH="$VPP_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
	"$VPP_CTL_BIN" -s "$VPP_SOCKET" "$@"
}
