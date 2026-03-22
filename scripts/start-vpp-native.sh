#!/usr/bin/env bash
# start-vpp-native.sh — Start VPP natively with AF_XDP (no container, no DPDK bind)
#
# Validated topology: single-node DAC (X710 port0 ↔ port1 back-to-back)
# Requires: i40e driver, hugepages, VPP built with af_xdp_plugin.so
#
# Environment overrides:
#   VPP_ROOT                   VPP build root (auto-detected from vmoongen-env.sh)
#   VMOONGEN_VPP_PORT0         kernel interface name for left arm  (default: enp2s0f0np0)
#   VMOONGEN_VPP_PORT1         kernel interface name for right arm (default: enp2s0f1np1)
#   VMOONGEN_VPP_PORT0_IP      IP/prefix for port0 (default: 10.0.1.1/30)
#   VMOONGEN_VPP_PORT1_IP      IP/prefix for port1 (default: 10.0.2.1/30)
#   VMOONGEN_VPP_RX_QUEUES     RSS queues per NIC before AF_XDP bind (default: 1)
#   VMOONGEN_VPP_CONF          VPP config file path (default: /run/vpp/vpp-afxdp.conf)
#   VMOONGEN_VPP_WORKERS       VPP worker thread count in config (default: 2)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

mkdir -p "$LOGDIR" "$VPP_RUN_DIR"
VPP_LOG="$LOGDIR/vpp-native.log"

# ── defaults ────────────────────────────────────────────────────────────────
PORT0="${VMOONGEN_VPP_PORT0:-enp2s0f0np0}"
PORT1="${VMOONGEN_VPP_PORT1:-enp2s0f1np1}"
PORT0_IP="${VMOONGEN_VPP_PORT0_IP:-10.0.1.1/30}"
PORT1_IP="${VMOONGEN_VPP_PORT1_IP:-10.0.2.1/30}"
RX_QUEUES="${VMOONGEN_VPP_RX_QUEUES:-1}"
VPP_WORKERS="${VMOONGEN_VPP_WORKERS:-2}"
VPP_CONF="${VMOONGEN_VPP_CONF:-/run/vpp/vpp-afxdp.conf}"

VPP_INSTALL_DIR="$VPP_ROOT/build-root/install-vpp-native/vpp"
VPP_BIN_NATIVE="$VPP_INSTALL_DIR/bin/vpp"
VPP_VPPCTL_NATIVE="$VPP_INSTALL_DIR/bin/vppctl"
VPP_LIB_DIR="$VPP_INSTALL_DIR/lib/x86_64-linux-gnu"

log() {
  echo "[$(date '+%F %T')] [VPP-NATIVE] $*" | tee -a "$VPP_LOG"
}

fail() {
  echo "[$(date '+%F %T')] [VPP-NATIVE][ERROR] $*" | tee -a "$VPP_LOG" >&2
  exit 1
}

vppctl() {
  echo "$1" | LD_LIBRARY_PATH="$VPP_LIB_DIR" "$VPP_VPPCTL_NATIVE" -s "$VPP_SOCKET"
}

[[ -x "$VPP_BIN_NATIVE" ]]    || fail "VPP binary not found: $VPP_BIN_NATIVE"
[[ -x "$VPP_VPPCTL_NATIVE" ]] || fail "vppctl not found: $VPP_VPPCTL_NATIVE"
[[ -d "$VPP_LIB_DIR" ]]       || fail "VPP lib dir not found: $VPP_LIB_DIR"

log "VPP binary: $VPP_BIN_NATIVE"
log "Port0: $PORT0 ($PORT0_IP)  Port1: $PORT1 ($PORT1_IP)"

# ── 1. Stop existing VPP ────────────────────────────────────────────────────
log "Stopping any existing VPP"
pkill -f "vpp.*afxdp" 2>/dev/null || true
pkill vpp 2>/dev/null || true
sleep 1

# ── 2. Detach stale XDP programs ────────────────────────────────────────────
log "Detaching stale XDP programs from $PORT0 $PORT1"
ip link set "$PORT0" xdp off 2>/dev/null || true
ip link set "$PORT1" xdp off 2>/dev/null || true

# ── 3. Set NICs to single queue (all RSS traffic → queue 0 → AF_XDP socket) ─
log "Setting NICs to $RX_QUEUES combined queue(s)"
ethtool -L "$PORT0" combined "$RX_QUEUES" 2>/dev/null || \
  log "WARNING: ethtool -L $PORT0 failed (continuing)"
ethtool -L "$PORT1" combined "$RX_QUEUES" 2>/dev/null || \
  log "WARNING: ethtool -L $PORT1 failed (continuing)"

# ── 4. Write VPP config if it doesn't exist ─────────────────────────────────
mkdir -p "$(dirname "$VPP_CONF")"
if [[ ! -f "$VPP_CONF" ]]; then
  log "Writing VPP config at $VPP_CONF"
  cat > "$VPP_CONF" <<EOF
unix {
  nodaemon
  log $LOGDIR/vpp-native.log
  cli-listen $VPP_SOCKET
}
api-trace { on }
api-segment { prefix vpp }
socksvr { default }
cpu { workers $VPP_WORKERS }
session { enable }
EOF
fi

# ── 5. Start VPP ────────────────────────────────────────────────────────────
log "Starting VPP (config: $VPP_CONF)"
rm -f "$VPP_SOCKET"

nohup env LD_LIBRARY_PATH="$VPP_LIB_DIR" \
  "$VPP_BIN_NATIVE" -c "$VPP_CONF" >>"$VPP_LOG" 2>&1 &
VPP_PID=$!
echo "$VPP_PID" > "$VPP_RUN_DIR/vpp.pid"
log "VPP pid=$VPP_PID"

# ── 6. Wait for CLI socket (up to 30s) ──────────────────────────────────────
log "Waiting for VPP CLI socket at $VPP_SOCKET..."
for i in $(seq 1 30); do
  sleep 1
  [[ -S "$VPP_SOCKET" ]] && { log "CLI socket ready after ${i}s"; break; }
  kill -0 "$VPP_PID" 2>/dev/null || fail "VPP process died. Check $VPP_LOG"
done
[[ -S "$VPP_SOCKET" ]] || fail "VPP CLI socket not created after 30s"

# ── 7. Create AF_XDP interfaces (copy mode, no ZC) ──────────────────────────
log "Creating AF_XDP interface port0 ($PORT0)"
vppctl "create interface af_xdp host-if $PORT0 name port0 num-rx-queues $RX_QUEUES no-zero-copy"

log "Creating AF_XDP interface port1 ($PORT1)"
vppctl "create interface af_xdp host-if $PORT1 name port1 num-rx-queues $RX_QUEUES no-zero-copy"

# ── 8. Configure IPs and bring up ───────────────────────────────────────────
log "Configuring interfaces"
for cmd in \
  "set interface state port0 up" \
  "set interface state port1 up" \
  "set interface ip address port0 $PORT0_IP" \
  "set interface ip address port1 $PORT1_IP"; do
  vppctl "$cmd"
done

# ── 9. Verify ───────────────────────────────────────────────────────────────
log "VPP interfaces:"
LD_LIBRARY_PATH="$VPP_LIB_DIR" "$VPP_VPPCTL_NATIVE" -s "$VPP_SOCKET" show interface | \
  tee -a "$VPP_LOG"

log "VPP native startup complete"
log "  port0=$PORT0 $PORT0_IP  port1=$PORT1 $PORT1_IP"
log "  CLI socket: $VPP_SOCKET"
