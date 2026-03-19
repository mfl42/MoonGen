#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

CTL="$ROOT/scripts/vmoongenctl"

SCENARIO="${VMOONGEN_CAMPAIGN_SCENARIO:-$ROOT/examples/scenario-dsl/livebox_2arm_efficiency_f1.lua}"
WORKERS="${VMOONGEN_CAMPAIGN_WORKERS:-4}"
ITERATIONS="${VMOONGEN_CAMPAIGN_ITERATIONS:-4}"
STEP_S="${VMOONGEN_CAMPAIGN_STEP_S:-0.1}"
RUN_WINDOW="${VMOONGEN_CAMPAIGN_RUN_WINDOW:-}"
OUT_DIR="${VMOONGEN_CAMPAIGN_OUT_DIR:-/tmp/vmoongen-campaign-cache-$(date -u +%Y%m%d-%H%M%S)}"
P_CORES="${VMOONGEN_CAMPAIGN_P_CORES:-2}"
E_CORES="${VMOONGEN_CAMPAIGN_E_CORES:-2}"
CAPTURE_PERF="${VMOONGEN_CAMPAIGN_CAPTURE_PERF:-1}"
PERF_STAT_FILE="${VMOONGEN_CAMPAIGN_PERF_STAT_FILE:-}"
PERF_EVENTS="${VMOONGEN_CAMPAIGN_PERF_EVENTS:-L1-dcache-loads,L1-dcache-load-misses,l2_rqsts.references,l2_rqsts.miss,LLC-loads,LLC-load-misses}"
CAPTURE_PCAP="${VMOONGEN_CAMPAIGN_CAPTURE_PCAP:-1}"
PCAP_IFACE="${VMOONGEN_CAMPAIGN_PCAP_IFACE:-}"
PCAP_MAX_BYTES="${VMOONGEN_CAMPAIGN_PCAP_BYTES:-102400}"
PCAP_RAW_FILE="${VMOONGEN_CAMPAIGN_PCAP_RAW_FILE:-}"
PCAP_FILE="${VMOONGEN_CAMPAIGN_PCAP_FILE:-}"
PCAP_PID=""
PCAP_ENGINE=""

usage() {
  cat <<USAGE
Usage:
  scripts/scenario-campaign-cache.sh [scenario.lua] [options]

Options:
  --workers N
  --iterations N
  --step-s N
  --run-window 5m|15m|30m|60m|Ns
  --out-dir DIR
  --p-cores N
  --e-cores N
  --perf-stat-file FILE
  --perf-events CSV
  --pcap-iface IFACE
  --pcap-bytes N
  --pcap-file FILE
  --no-pcap
  --no-perf
USAGE
}

log() {
  printf '[scenario-campaign-cache] %s\n' "$*"
}

ensure_core_isolation() {
  local auto_plan="${VMOONGEN_AUTO_CORE_ISOLATION_PLAN:-1}"
  if [[ "$auto_plan" == "1" && -d /sys/devices/system/cpu ]]; then
    if [[ -z "${VMOONGEN_VPP_CPUSET:-}" || -z "${VMOONGEN_CLIENT_CPUSET:-}" || -z "${VMOONGEN_SYSTEM_CPUSET:-}" || -z "${VMOONGEN_SYSTEM_E_CPUSET:-}" ]]; then
      log "No core isolation cpuset detected; generating affinity plan"
      "$ROOT/scripts/plan-core-affinity.sh" \
        --reserve-p-cores "${VMOONGEN_RESERVE_P_CORES:-4}" \
        --reserve-e-clients "${VMOONGEN_RESERVE_E_CLIENTS:-all}" \
        --system-min-cpus "${VMOONGEN_SYSTEM_MIN_CPUS:-2}" \
        --system-min-e-cores "${VMOONGEN_SYSTEM_MIN_E_CORES:-2}" \
        --write-env "$VMOONGEN_AFFINITY_ENV" >/dev/null
      # shellcheck disable=SC1090
      source "$VMOONGEN_AFFINITY_ENV"
    fi
  fi

  if ! vmoongen_validate_core_isolation 2>/dev/null; then
    if [[ "$auto_plan" == "1" && -d /sys/devices/system/cpu ]]; then
      log "Core isolation out of policy; regenerating affinity plan"
      "$ROOT/scripts/plan-core-affinity.sh" \
        --reserve-p-cores "${VMOONGEN_RESERVE_P_CORES:-4}" \
        --reserve-e-clients "${VMOONGEN_RESERVE_E_CLIENTS:-all}" \
        --system-min-cpus "${VMOONGEN_SYSTEM_MIN_CPUS:-2}" \
        --system-min-e-cores "${VMOONGEN_SYSTEM_MIN_E_CORES:-2}" \
        --write-env "$VMOONGEN_AFFINITY_ENV" >/dev/null
      # shellcheck disable=SC1090
      source "$VMOONGEN_AFFINITY_ENV"
    fi
    if ! vmoongen_validate_core_isolation; then
      echo "[ERROR] core isolation check failed; aborting campaign." >&2
      exit 2
    fi
  fi
}

default_pcap_iface() {
  if [[ -n "${PCAP_IFACE:-}" ]]; then
    return
  fi
  local first
  first="$(echo "${VMOONGEN_IFACES:-}" | awk '{print $1}')"
  PCAP_IFACE="${first:-}"
}

start_pcap_capture() {
  [[ "$CAPTURE_PCAP" == "1" ]] || return 0
  default_pcap_iface
  if [[ -z "$PCAP_IFACE" ]]; then
    log "pcap disabled: no interface selected"
    CAPTURE_PCAP="0"
    return 0
  fi

  if [[ -z "$PCAP_RAW_FILE" ]]; then
    PCAP_RAW_FILE="$OUT_DIR/campaign-capture-raw.pcap"
  fi
  if [[ -z "$PCAP_FILE" ]]; then
    PCAP_FILE="$OUT_DIR/campaign-capture.pcap"
  fi

  local -a cmd=()
  if command -v tcpdump >/dev/null 2>&1; then
    PCAP_ENGINE="tcpdump"
    cmd=(tcpdump -i "$PCAP_IFACE" -s 192 -U -w "$PCAP_RAW_FILE")
  else
    PCAP_ENGINE="py-afpacket"
    cmd=(python3 "$ROOT/tools/pcap_capture.py" --iface "$PCAP_IFACE" --snaplen 192 --output "$PCAP_RAW_FILE")
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    cmd=(sudo -n "${cmd[@]}")
  fi

  log "starting pcap capture on $PCAP_IFACE via $PCAP_ENGINE (target ${PCAP_MAX_BYTES} bytes)"
  "${cmd[@]}" >"$OUT_DIR/pcap-capture.log" 2>&1 &
  PCAP_PID="$!"
  sleep 1
  if ! kill -0 "$PCAP_PID" 2>/dev/null; then
    log "pcap capture failed to start; see $OUT_DIR/pcap-capture.log"
    CAPTURE_PCAP="0"
    PCAP_PID=""
  fi
}

stop_pcap_capture() {
  [[ "$CAPTURE_PCAP" == "1" ]] || return 0
  if [[ -n "$PCAP_PID" ]]; then
    kill "$PCAP_PID" >/dev/null 2>&1 || true
    wait "$PCAP_PID" >/dev/null 2>&1 || true
    PCAP_PID=""
  fi

  if [[ -f "$PCAP_RAW_FILE" ]]; then
    if python3 "$ROOT/tools/pcap_trim.py" --input "$PCAP_RAW_FILE" --output "$PCAP_FILE" --max-bytes "$PCAP_MAX_BYTES" >"$OUT_DIR/pcap-trim.log" 2>&1; then
      log "pcap capture: $PCAP_FILE"
      log "pcap trim log: $OUT_DIR/pcap-trim.log"
    else
      log "pcap trim failed; keeping raw file: $PCAP_RAW_FILE"
    fi
  else
    log "pcap raw file missing; capture may have failed"
  fi
}

on_exit() {
  stop_pcap_capture || true
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -*)
      ;;
    *)
      SCENARIO="$1"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workers)
      WORKERS="${2:-}"
      shift 2
      ;;
    --iterations)
      ITERATIONS="${2:-}"
      shift 2
      ;;
    --step-s)
      STEP_S="${2:-}"
      shift 2
      ;;
    --run-window)
      RUN_WINDOW="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --p-cores)
      P_CORES="${2:-}"
      shift 2
      ;;
    --e-cores)
      E_CORES="${2:-}"
      shift 2
      ;;
    --perf-stat-file)
      PERF_STAT_FILE="${2:-}"
      shift 2
      ;;
    --perf-events)
      PERF_EVENTS="${2:-}"
      shift 2
      ;;
    --pcap-iface)
      PCAP_IFACE="${2:-}"
      shift 2
      ;;
    --pcap-bytes)
      PCAP_MAX_BYTES="${2:-}"
      shift 2
      ;;
    --pcap-file)
      PCAP_FILE="${2:-}"
      shift 2
      ;;
    --no-pcap)
      CAPTURE_PCAP="0"
      shift
      ;;
    --no-perf)
      CAPTURE_PERF="0"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "$SCENARIO" ]]; then
  echo "[ERROR] scenario file not found: $SCENARIO" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
if [[ -z "$PERF_STAT_FILE" ]]; then
  PERF_STAT_FILE="$OUT_DIR/perf-stat.txt"
fi
trap on_exit EXIT

ensure_core_isolation

CAMPAIGN_CMD=(
  "$CTL" scenario-campaign "$SCENARIO"
  --workers "$WORKERS"
  --iterations "$ITERATIONS"
  --step-s "$STEP_S"
  --out-dir "$OUT_DIR"
)
if [[ -n "$RUN_WINDOW" ]]; then
  CAMPAIGN_CMD+=(--run-window "$RUN_WINDOW")
fi

log "scenario: $SCENARIO"
log "out_dir: $OUT_DIR"
if [[ -n "$RUN_WINDOW" ]]; then
  log "run_window: $RUN_WINDOW"
fi
if [[ "$CAPTURE_PCAP" == "1" ]]; then
  log "pcap_target_bytes: $PCAP_MAX_BYTES"
fi

start_pcap_capture

if [[ "$CAPTURE_PERF" == "1" && -x "$(command -v perf || true)" ]]; then
  log "running campaign with perf stat"
  vmoongen_run_on_client_cpuset perf stat -o "$PERF_STAT_FILE" -e "$PERF_EVENTS" "${CAMPAIGN_CMD[@]}" > "$OUT_DIR/campaign-output.json"
else
  if [[ "$CAPTURE_PERF" == "1" ]]; then
    log "perf not available; running campaign without cache counters"
  fi
  vmoongen_run_on_client_cpuset "${CAMPAIGN_CMD[@]}" > "$OUT_DIR/campaign-output.json"
fi

BEST_RUN_DIR="$(
python3 - "$OUT_DIR" <<'PY'
import glob
import json
import os
import sys

out_dir = sys.argv[1]
campaign_path = os.path.join(out_dir, "campaign-results.json")
data = {}
try:
    with open(campaign_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    pass

target = None
best = (data.get("best_known") or {}).get("value")
runs = data.get("runs") or []
for idx, run in enumerate(runs, start=1):
    if run.get("verdict") == "pass" and run.get("candidate_value") == best:
        target = (idx, int(run.get("candidate_value")))
        break
if target is None and runs:
    run = runs[0]
    target = (1, int(run.get("candidate_value", 0)))

if target is not None:
    idx, cps = target
    direct = os.path.join(out_dir, "runs", f"{idx:03d}-{cps}")
    if os.path.isdir(direct):
        print(direct)
        raise SystemExit(0)

dirs = sorted(glob.glob(os.path.join(out_dir, "runs", "*")))
if dirs:
    print(dirs[0])
    raise SystemExit(0)

print(out_dir)
PY
)"

EFF_ARGS=(
  "$CTL" scenario-efficiency "$BEST_RUN_DIR"
  --p-cores "$P_CORES"
  --e-cores "$E_CORES"
  --write-report
  --report-file "$OUT_DIR/cache-efficiency-summary.txt"
)
if [[ -s "$PERF_STAT_FILE" ]]; then
  EFF_ARGS+=(--perf-stat-file "$PERF_STAT_FILE")
fi

log "best_run_dir: $BEST_RUN_DIR"
vmoongen_run_on_client_cpuset "${EFF_ARGS[@]}" > "$OUT_DIR/cache-efficiency.txt"
vmoongen_run_on_client_cpuset "${EFF_ARGS[@]}" --emit-json > "$OUT_DIR/cache-efficiency.json"

log "campaign results: $OUT_DIR/campaign-results.json"
log "efficiency text: $OUT_DIR/cache-efficiency.txt"
log "efficiency summary: $OUT_DIR/cache-efficiency-summary.txt"
log "efficiency json: $OUT_DIR/cache-efficiency.json"
if [[ -s "$PERF_STAT_FILE" ]]; then
  log "perf stat: $PERF_STAT_FILE"
fi
