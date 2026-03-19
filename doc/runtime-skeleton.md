# Runtime Skeleton v1

This document describes the deterministic runtime skeleton used for early integration tests.

Scope:

- consume compiled DSL scenario and worker plan
- simulate per-worker micro-flow progression by phase
- export deterministic artifacts

This is intentionally not the final dataplane runtime.

## Inputs

The runtime skeleton consumes:

1. DSL scenario file (`test "..." { ... }`)
2. worker planning options:
   - worker count
   - shard strategy
   - simulation step

## Tool

Run:

```bash
luajit tools/scenario_runtime_skeleton.lua examples/scenario-dsl/livebox_http_nat44.lua --workers 8 --step-s 1 --shard-strategy contiguous --out-dir /tmp/vmoongen-sim
```

Replay from an existing worker plan:

```bash
luajit tools/scenario_runtime_skeleton.lua --worker-plan-file /tmp/worker-plan.json --step-s 1 --target-cps-override 180000 --out-dir /tmp/vmoongen-replay
```

Outputs:

- `/tmp/vmoongen-sim/run-summary.json`
- `/tmp/vmoongen-sim/phase-summary.json`
- `/tmp/vmoongen-sim/worker-metrics.json`

## Runtime Model

Per tick:

- resolve active phase (`start`, `ramp`, `steady`, `finish`, `end`)
- resolve target cps for the phase
- split target cps across active workers
- update per-worker active sessions, retries, latency proxy, and drop proxy
- aggregate run-level and phase-level metrics

This model is deterministic and intended for integration and control-loop bring-up.

## Export Contract

Artifacts are compatible with:

- [schemas/ai-sidecar/run-summary.schema.json](schemas/ai-sidecar/run-summary.schema.json)
- [schemas/ai-sidecar/phase-summary.schema.json](schemas/ai-sidecar/phase-summary.schema.json)

Additional worker-level export:

- `worker-metrics.json` (runtime-specific helper artifact)
- includes `role` and `arm` per worker (`left` / `right`)

## Dichotomy Campaign Tool

Run a dichotomy campaign around CPS:

```bash
luajit tools/scenario_campaign.lua examples/scenario-dsl/livebox_http_nat44.lua --workers 8 --iterations 8 --out-dir /tmp/vmoongen-campaign
```

Outputs:

- `/tmp/vmoongen-campaign/campaign-results.json`
- per-run artifacts under `/tmp/vmoongen-campaign/runs/`

This uses:

- `--target-cps-override` internally on ramp/steady phases
- acceptance thresholds from DSL `acceptance { ... }` block

## One-shot Smoke

Run all scenario checks (`plan`, `worker-plan`, `scenario-v1`, `run`, `replay`, `campaign`) in one command:

```bash
scripts/scenario-smoke.sh local --workers 4 --iterations 4
```

Run both local and venus:

```bash
scripts/scenario-smoke.sh both --host mfl42@192.168.1.220 --workers 4 --iterations 4
```

## Related Files

- [lua/runtime_microflow.lua](../lua/runtime_microflow.lua)
- [lua/scenario_planner.lua](../lua/scenario_planner.lua)
- [tools/scenario_runtime_skeleton.lua](../tools/scenario_runtime_skeleton.lua)
- [schemas/worker-plan/worker-plan-v1.schema.json](schemas/worker-plan/worker-plan-v1.schema.json)
