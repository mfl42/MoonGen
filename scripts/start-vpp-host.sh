#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"
mkdir -p "$LOGDIR" "$VPP_RUN_DIR"

VPP_LOG="$LOGDIR/vpp.log"
CONTAINER_VPP_ROOT="$VMOONGEN_VPP_WORKDIR"
CONTAINER_VPP_INSTALL_DIR="$CONTAINER_VPP_ROOT/build-root/install-vpp-native/vpp"
CONTAINER_VPP_SESSION_CONF="$CONTAINER_VPP_ROOT/run/vpp-session.conf"
RENDER_VPP_CONF="${VMOONGEN_VPP_RENDER_CONFIG:-0}"

render_session_config() {
  local tmp_conf backup_conf

  tmp_conf="$(mktemp "$VPP_RUN_DIR/vpp-session.conf.render.XXXXXX")"
  "$ROOT/scripts/render-vpp-session-conf.sh" "$tmp_conf"

  if [[ -f "$VPP_SESSION_CONF" ]]; then
    backup_conf="$VPP_SESSION_CONF.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$VPP_SESSION_CONF" "$backup_conf"
    echo "[HOST] Backed up existing VPP config to $backup_conf"
  fi

  mv "$tmp_conf" "$VPP_SESSION_CONF"
}

echo "[HOST] Stopping previous VPP container if any"
podman rm -f "$VMOONGEN_VPP_CONTAINER" >/dev/null 2>&1 || true
rm -f "$VPP_SOCKET"

if [[ "$RENDER_VPP_CONF" == "1" || ! -f "$VPP_SESSION_CONF" ]]; then
  echo "[HOST] Rendering VPP session config at $VPP_SESSION_CONF"
  render_session_config
fi

vmoongen_require_file "$VPP_BIN" "VPP binary"
vmoongen_require_file "$VPP_SESSION_CONF" "VPP session config"

echo "[HOST] Starting VPP container $VMOONGEN_VPP_CONTAINER"
nohup podman run --name "$VMOONGEN_VPP_CONTAINER" --rm \
  -v "$VPP_ROOT:$CONTAINER_VPP_ROOT:Z" \
  -w "$CONTAINER_VPP_ROOT" \
  "$VMOONGEN_VPP_IMAGE" \
  /bin/bash -lc \
  "LD_LIBRARY_PATH=\"$CONTAINER_VPP_INSTALL_DIR/lib/x86_64-linux-gnu\" \"$CONTAINER_VPP_INSTALL_DIR/bin/vpp\" -c \"$CONTAINER_VPP_SESSION_CONF\"" \
  >"$VPP_LOG" 2>&1 &

sleep 5

echo "[HOST] Checking VPP socket"
if ! vmoongen_vppctl show version; then
  echo "[HOST] VPP did not become reachable. Recent log follows:" >&2
  tail -n 40 "$VPP_LOG" >&2 || true
  exit 1
fi

echo "[HOST] VPP started"
