#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

CTL="$ROOT/scripts/vmoongenctl"

MODE="local"
REMOTE_HOST="${VMOONGEN_SMOKE_HOST:-}"
REMOTE_REPO="${VMOONGEN_SMOKE_REMOTE_REPO:-/home/mfl42/Projects/vMoonGen}"
SCENARIO="${VMOONGEN_SMOKE_SCENARIO:-$ROOT/examples/scenario-dsl/livebox_http_nat44.lua}"
REMOTE_SCENARIO=""
WORKERS="${VMOONGEN_SMOKE_WORKERS:-4}"
STEP_S="${VMOONGEN_SMOKE_STEP_S:-0.1}"
ITERATIONS="${VMOONGEN_SMOKE_ITERATIONS:-4}"
TARGET_CPS_OVERRIDE="${VMOONGEN_SMOKE_TARGET_CPS_OVERRIDE:-120000}"
SHARD_STRATEGY="${VMOONGEN_SMOKE_SHARD_STRATEGY:-contiguous}"
OUT_ROOT="${VMOONGEN_SMOKE_OUT_ROOT:-/tmp/vmoongen-scenario-smoke}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"

usage() {
  cat <<USAGE
Usage:
  scripts/scenario-smoke.sh [local|remote|both] [options]

Options:
  --host <user@ip>             Remote host for remote/both mode
  --remote-repo <path>         Remote repo root (default: /home/mfl42/Projects/vMoonGen)
  --scenario <path>            Local scenario file (default: examples/scenario-dsl/livebox_http_nat44.lua)
  --remote-scenario <path>     Remote scenario file path (default: mapped from --scenario)
  --workers <n>                Worker count (default: 4)
  --step-s <n>                 Runtime step seconds (default: 0.1)
  --iterations <n>             Campaign iterations (default: 4)
  --target-cps-override <n>    Replay cps override (default: 120000)
  --shard-strategy <name>      contiguous or round_robin (default: contiguous)
  --out-root <path>            Root output directory (default: /tmp/vmoongen-scenario-smoke)
USAGE
}

log() {
  printf '[scenario-smoke] %s\n' "$*"
}

fail() {
  printf '[scenario-smoke][ERROR] %s\n' "$*" >&2
  exit 1
}

summary_run() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" <<'PY'
import json, sys
path = sys.argv[1]
label = sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
m = data.get("metrics", {})
print(f"[{label}] verdict={data.get('verdict')} cps={m.get('cps')} drop_rate={m.get('drop_rate')} latency_us_p95={m.get('latency_us_p95')}")
PY
}

summary_campaign() {
  local file="$1"
  local label="$2"
  python3 - "$file" "$label" <<'PY'
import json, sys
path = sys.argv[1]
label = sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
best = data.get("best_known") or {}
next_c = data.get("recommended_next") or {}
print(f"[{label}] best_cps={best.get('value')} next_candidate={next_c.get('candidate_value')} search={data.get('search_method')}")
PY
}

run_local() {
  local base="$OUT_ROOT/local/$STAMP"
  local worker_plan="$base/worker-plan.json"

  [[ -f "$SCENARIO" ]] || fail "Scenario file not found: $SCENARIO"
  vmoongen_have_luajit || fail "LuaJIT not available locally (VMOONGEN_LUAJIT_BIN is empty)."

  mkdir -p "$base"
  log "Local smoke in $base"

  "$CTL" scenario-plan "$SCENARIO" > "$base/plan.json"
  "$CTL" scenario-worker-plan "$SCENARIO" --workers "$WORKERS" --shard-strategy "$SHARD_STRATEGY" > "$worker_plan"
  "$CTL" scenario-v1 "$SCENARIO" > "$base/scenario-v1.json"
  "$CTL" scenario-run "$SCENARIO" --workers "$WORKERS" --step-s "$STEP_S" --shard-strategy "$SHARD_STRATEGY" --out-dir "$base/run" > "$base/run-output.json"
  "$CTL" scenario-replay "$worker_plan" --step-s "$STEP_S" --target-cps-override "$TARGET_CPS_OVERRIDE" --out-dir "$base/replay" > "$base/replay-output.json"
  "$CTL" scenario-campaign "$SCENARIO" --workers "$WORKERS" --iterations "$ITERATIONS" --step-s "$STEP_S" --shard-strategy "$SHARD_STRATEGY" --out-dir "$base/campaign" > "$base/campaign-output.json"

  summary_run "$base/run/run-summary.json" "local run"
  summary_run "$base/replay/run-summary.json" "local replay"
  summary_campaign "$base/campaign/campaign-results.json" "local campaign"
  log "Local artifacts: $base"
}

run_remote() {
  local base="$OUT_ROOT/remote/$STAMP"
  local remote_scenario="$REMOTE_SCENARIO"
  local ssh_base=(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$REMOTE_HOST")

  [[ -n "$REMOTE_HOST" ]] || fail "--host is required in remote/both mode."
  if [[ -z "$remote_scenario" ]]; then
    if [[ "$SCENARIO" == "$ROOT/"* ]]; then
      remote_scenario="$REMOTE_REPO/${SCENARIO#"$ROOT/"}"
    else
      remote_scenario="$SCENARIO"
    fi
  fi

  log "Remote smoke on $REMOTE_HOST in $base"
  "${ssh_base[@]}" "echo ok-ssh >/dev/null"
  "${ssh_base[@]}" "mkdir -p '$base'"

  "${ssh_base[@]}" "'$REMOTE_REPO/scripts/vmoongenctl' scenario-plan '$remote_scenario' > '$base/plan.json'"
  "${ssh_base[@]}" "'$REMOTE_REPO/scripts/vmoongenctl' scenario-worker-plan '$remote_scenario' --workers '$WORKERS' --shard-strategy '$SHARD_STRATEGY' > '$base/worker-plan.json'"
  "${ssh_base[@]}" "'$REMOTE_REPO/scripts/vmoongenctl' scenario-v1 '$remote_scenario' > '$base/scenario-v1.json'"
  "${ssh_base[@]}" "'$REMOTE_REPO/scripts/vmoongenctl' scenario-run '$remote_scenario' --workers '$WORKERS' --step-s '$STEP_S' --shard-strategy '$SHARD_STRATEGY' --out-dir '$base/run' > '$base/run-output.json'"
  "${ssh_base[@]}" "'$REMOTE_REPO/scripts/vmoongenctl' scenario-replay '$base/worker-plan.json' --step-s '$STEP_S' --target-cps-override '$TARGET_CPS_OVERRIDE' --out-dir '$base/replay' > '$base/replay-output.json'"
  "${ssh_base[@]}" "'$REMOTE_REPO/scripts/vmoongenctl' scenario-campaign '$remote_scenario' --workers '$WORKERS' --iterations '$ITERATIONS' --step-s '$STEP_S' --shard-strategy '$SHARD_STRATEGY' --out-dir '$base/campaign' > '$base/campaign-output.json'"

  "${ssh_base[@]}" "python3 -c \"import json; d=json.load(open('$base/run/run-summary.json')); m=d.get('metrics', {}); print('[remote run] verdict=%s cps=%s drop_rate=%s latency_us_p95=%s' % (d.get('verdict'), m.get('cps'), m.get('drop_rate'), m.get('latency_us_p95')))\""
  "${ssh_base[@]}" "python3 -c \"import json; d=json.load(open('$base/replay/run-summary.json')); m=d.get('metrics', {}); print('[remote replay] verdict=%s cps=%s drop_rate=%s latency_us_p95=%s' % (d.get('verdict'), m.get('cps'), m.get('drop_rate'), m.get('latency_us_p95')))\""
  "${ssh_base[@]}" "python3 -c \"import json; d=json.load(open('$base/campaign/campaign-results.json')); b=(d.get('best_known') or {}); n=(d.get('recommended_next') or {}); print('[remote campaign] best_cps=%s next_candidate=%s search=%s' % (b.get('value'), n.get('candidate_value'), d.get('search_method')))\""
  log "Remote artifacts on $REMOTE_HOST: $base"
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    local|remote|both)
      MODE="$1"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="${2:-}"
      shift 2
      ;;
    --remote-repo)
      REMOTE_REPO="${2:-}"
      shift 2
      ;;
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --remote-scenario)
      REMOTE_SCENARIO="${2:-}"
      shift 2
      ;;
    --workers)
      WORKERS="${2:-}"
      shift 2
      ;;
    --step-s)
      STEP_S="${2:-}"
      shift 2
      ;;
    --iterations)
      ITERATIONS="${2:-}"
      shift 2
      ;;
    --target-cps-override)
      TARGET_CPS_OVERRIDE="${2:-}"
      shift 2
      ;;
    --shard-strategy)
      SHARD_STRATEGY="${2:-}"
      shift 2
      ;;
    --out-root)
      OUT_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

case "$MODE" in
  local)
    run_local
    ;;
  remote)
    run_remote
    ;;
  both)
    run_local
    run_remote
    ;;
  *)
    fail "Unknown mode: $MODE"
    ;;
esac

