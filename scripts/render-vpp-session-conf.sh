#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

TARGET_CONF="${1:-$VPP_SESSION_CONF}"
WORKERS="${VMOONGEN_VPP_WORKERS:-2}"
RX_QUEUES="${VMOONGEN_VPP_RX_QUEUES:-1}"
TX_QUEUES="${VMOONGEN_VPP_TX_QUEUES:-1}"
RX_QUEUE_SIZE="${VMOONGEN_VPP_RX_QUEUE_SIZE:-512}"
TX_QUEUE_SIZE="${VMOONGEN_VPP_TX_QUEUE_SIZE:-512}"
FASTPATH_MODE="${VMOONGEN_VPP_FASTPATH_MODE:-auto}"

containerize_vpp_path() {
  local path="$1"
  if [[ "$path" == "$VPP_ROOT"* ]]; then
    printf '%s\n' "${VMOONGEN_VPP_WORKDIR}${path#$VPP_ROOT}"
  else
    printf '%s\n' "$path"
  fi
}

CLI_SOCKET_IN_CONTAINER="$(containerize_vpp_path "$VPP_SOCKET")"
RUN_LOG_IN_CONTAINER="$(containerize_vpp_path "$VPP_RUN_DIR/vpp.log")"
RESOLVED_FASTPATH_MODE="$(vmoongen_vpp_detect_fastpath_mode "$FASTPATH_MODE" 2>/dev/null || true)"

mkdir -p "$(dirname "$TARGET_CONF")"

if [[ -z "$RESOLVED_FASTPATH_MODE" ]]; then
  echo "[ERROR] Unable to resolve a supported VPP fast-path mode for this host." >&2
  vmoongen_vpp_fastpath_failure_hint "$FASTPATH_MODE" >&2
  exit 1
fi

{
cat <<EOF_CONF
unix {
  nodaemon
  log $RUN_LOG_IN_CONTAINER
  cli-listen $CLI_SOCKET_IN_CONTAINER
}

api-trace {
  on
}

api-segment {
  prefix vpp
}

socksvr {
  default
}
EOF_CONF

if [[ "$WORKERS" =~ ^[0-9]+$ ]] && [[ "$WORKERS" -gt 0 ]]; then
cat <<EOF_CPU
cpu {
  workers $WORKERS
}
EOF_CPU
fi

if [[ "$RESOLVED_FASTPATH_MODE" == "classic-dpdk" ]]; then
cat <<EOF_CONF

plugins {
  plugin dpdk_plugin.so { enable }
}

session {
  enable
}

dpdk {
  # Cross-port DAC topology:
  # - one client role on one X710 port
  # - one server role on the other X710 port
  # - no client/server loop on the same port
  uio-driver vfio-pci
  dev default {
    num-rx-queues $RX_QUEUES
    num-tx-queues $TX_QUEUES
  }
  dev $VMOONGEN_NIC1
  dev $VMOONGEN_NIC2
}
EOF_CONF
elif [[ "$RESOLVED_FASTPATH_MODE" == "dev-ige" || "$RESOLVED_FASTPATH_MODE" == "dev-iavf" ]]; then
  DRIVER_NAME="${RESOLVED_FASTPATH_MODE#dev-}"
cat <<EOF_CONF

session {
  enable
}

devices {
  # Cross-port DAC topology:
  # - one client role on one X710 port
  # - one server role on the other X710 port
  # - no client/server loop on the same port
  dev pci/$VMOONGEN_NIC1 {
    driver $DRIVER_NAME
    port 0 {
      name $VMOONGEN_VPP_IFACE1_NAME
      num-rx-queues $RX_QUEUES
      num-tx-queues $TX_QUEUES
      rx-queue-size $RX_QUEUE_SIZE
      tx-queue-size $TX_QUEUE_SIZE
    }
  }
  dev pci/$VMOONGEN_NIC2 {
    driver $DRIVER_NAME
    port 0 {
      name $VMOONGEN_VPP_IFACE2_NAME
      num-rx-queues $RX_QUEUES
      num-tx-queues $TX_QUEUES
      rx-queue-size $RX_QUEUE_SIZE
      tx-queue-size $TX_QUEUE_SIZE
    }
  }
}
EOF_CONF
else
cat <<EOF_CONF

session {
  enable
}
EOF_CONF
fi
} >"$TARGET_CONF"

echo "Rendered VPP session config: $TARGET_CONF"
echo "CLI socket inside container: $CLI_SOCKET_IN_CONTAINER"
echo "Resolved VPP fast-path mode: $RESOLVED_FASTPATH_MODE"
echo "DAC ports: $VMOONGEN_NIC1 $VMOONGEN_NIC2"
