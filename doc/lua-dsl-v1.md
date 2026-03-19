# Lua DSL v1

This document defines the executable high-level Lua DSL used to describe vMoonGen test scenarios.

The DSL is intentionally hybrid-ready:

- default transport behavior: `microflow`
- optional high-fidelity mode: `vpp`

VPP remains the dataplane runtime. The DSL controls scenario intent, population model, and phase behavior.

## Goals

- describe realistic UE/CPE/server profiles
- describe `1-arm` and `2-arm` topologies
- describe graph template selection and feature toggles
- describe traffic behavior and TCP model choice
- describe phased benchmark execution

## Root Form

Each file defines one root block:

```lua
test "scenario_name" {
  mode = "2-arm",
  -- blocks...
}
```

Supported mode values:

- `1-arm`
- `2-arm`

## Blocks

Top-level blocks:

- `equipment { ... }`
- `topology { ... }`
- `graph { ... }`
- `traffic { ... }`
- `logic { ... }` (optional)
- `phases { ... }`
- `acceptance { ... }` (optional)
- `observability { ... }` (optional)

### equipment

Use profile objects:

```lua
equipment {
  profile "cpe_livebox" { kind = "CPE", nat44 = true },
  profile "ue_android"  { kind = "UE", apps = { "http", "https" } }
}
```

Optional nested behavior block per profile:

```lua
profile "ue_home_standard" {
  behavior {
    parallel_sessions = dist.uniform(1, 8)
  }
}
```

### topology

Optional nested blocks:

- `instances`
- `arms`
- `addressing`
- `placement`

```lua
topology {
  instances { cpe = 500, ue_per_cpe = dist.uniform(8, 32), servers = 12 },
  arms {
    traversal = "cross-arm",
    traffic_direction = "full_duplex",
    left_port_index = 0,
    right_port_index = 1,
    left_role = "client",
    right_role = "server"
  },
  addressing { wan_pool = "100.64.0.0/12", server_pool = "10.200.0.0/16" },
  placement { shard_by = "cpe", affinity = "queue_core_strict" }
}
```

`arms` design notes:

- `traversal` must be `cross-arm`
- `traffic_direction`:
  - `client_to_server`
  - `server_to_client`
  - `full_duplex` (`2-arm` only)
- `left_role` and `right_role`:
  - `2-arm`: `client` / `server` (must differ)
  - `1-arm`: left must be `client`, right must be `server` or `real-server`

### graph

```lua
graph {
  template = "tcp_nat44_firewall",
  transport_engine = "microflow",
  features = { nat44 = true, firewall = true, ipsec = false, gtpu = false }
}
```

`transport_engine` values:

- `microflow`
- `vpp`
- `stub`

### traffic

```lua
traffic {
  application "web_browsing" {
    transport = "tcp",
    dst_port = 80
  },

  tcp_model {
    engine = "microflow",
    fidelity = "medium",
    init_cwnd = 10
  }
}
```

### logic

```lua
logic {
  populations { cpe_count = 500, ue_count = 8000, public_ips = 64 },
  pacing { connection_rate = "adaptive", burstiness = 0.2 },
  tcp_behavior { slow_start = true, cwnd_growth = "reno-lite" }
}
```

### phases

Mandatory phase names:

- `start`
- `ramp`
- `steady`
- `finish`

Optional final phase:

- `phase_end`

`end` is a Lua keyword, so the DSL uses `phase_end` for the final block.

```lua
phases {
  start { duration = "10s" },
  ramp  { duration = "60s", target_cps = 200000 },
  steady { duration = "300s", hold_cps = 200000 },
  finish { duration = "20s", drain = true },
  phase_end { cleanup = true, export = { "latency", "errors", "flows" } }
}
```

Supported duration formats:

- numeric seconds: `10`
- strings: `300ms`, `10s`, `2m`, `1h`

`ramp` helper:

```lua
cps = ramp.linear(0, 200000)
```

### acceptance

Optional acceptance block used by `--scenario-v1` export:

```lua
acceptance {
  max_drop_rate = 0.0,
  max_latency_us_p95 = 1200,
  max_tcp_retries_setup = 3
}
```

## Helpers

Distribution helpers:

- `dist.uniform(a, b)`
- `dist.fixed(v)`
- `dist.lognormal(mu, sigma)`

Profile reference helper:

- `use_profile("profile.field")`

## Compiler Tool

Compile a DSL file to JSON plan:

```bash
luajit tools/scenario_dsl_compile.lua examples/scenario-dsl/livebox_http_nat44.lua --plan
```

Show normalized AST:

```bash
luajit tools/scenario_dsl_compile.lua examples/scenario-dsl/livebox_http_nat44.lua --ast
```

Export strict scenario schema JSON:

```bash
luajit tools/scenario_dsl_compile.lua examples/scenario-dsl/livebox_http_nat44.lua --scenario-v1
```

Build worker-sharded execution plan:

```bash
luajit tools/scenario_dsl_compile.lua examples/scenario-dsl/livebox_http_nat44.lua --worker-plan --workers 8 --shard-strategy contiguous
```

Worker plan output includes:

- sharding dimension (`cpe` or `ue`)
- per-worker shard ownership range
- per-worker estimated cps/microflow budget
- timeline/phases copied from compiled plan

## vmoongenctl Shortcuts

With environment loaded, equivalent commands are available:

```bash
scripts/vmoongenctl scenario-plan examples/scenario-dsl/livebox_http_nat44.lua
scripts/vmoongenctl scenario-v1 examples/scenario-dsl/livebox_http_nat44.lua
scripts/vmoongenctl scenario-worker-plan examples/scenario-dsl/livebox_http_nat44.lua --workers 8
scripts/vmoongenctl scenario-run examples/scenario-dsl/livebox_http_nat44.lua --workers 8 --out-dir /tmp/vmoongen-sim
scripts/vmoongenctl scenario-campaign examples/scenario-dsl/livebox_http_nat44.lua --workers 8 --iterations 8 --out-dir /tmp/vmoongen-campaign
scripts/vmoongenctl scenario-smoke both --host mfl42@192.168.1.220 --workers 4 --iterations 4
```

## Example Files

- [examples/scenario-dsl/livebox_http_nat44.lua](../examples/scenario-dsl/livebox_http_nat44.lua)
- [examples/scenario-dsl/client_1arm_real_servers.lua](../examples/scenario-dsl/client_1arm_real_servers.lua)
