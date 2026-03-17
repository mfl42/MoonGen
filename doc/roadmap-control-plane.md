# Control Plane Optimization Roadmap

This document describes the roadmap to optimize the vMoonGen control-plane by moving from
a CLI-based interaction with VPP (`vppctl`) to a faster binary API architecture.

Goal:

- reduce control-plane latency
- remove fragile text parsing
- enable structured responses
- maintain CLI fallback for debugging

---

# Current Architecture

Current control-plane request flow:

Lua
→ UNIX socket
→ Python daemon
→ vppctl
→ VPP CLI
→ text response
→ parse text

Issues:

- text formatting overhead
- text parsing complexity
- slower control operations
- less reliable automation

---

# Target Architecture

Future request flow:

Lua
→ UNIX socket
→ Python daemon
→ VPP binary API
→ structured response

Benefits:

- lower latency
- structured data
- no text parsing
- easier automation
- scalable control-plane

The architecture does not need to change at a high level. The main improvement is the backend under the daemon.

Keep:

- Lua client
- UNIX socket transport
- persistent Python daemon

Replace gradually:

- `vppctl`
- CLI text parsing
- per-request process overhead

Longer-term optimized model:

Lua / MoonGen
→ local daemon over UNIX socket
→ persistent VPP API session
→ typed requests
→ optional batching
→ structured response

---

# Phase 0 — Stabilize CLI Backend

Goal: ensure the existing system remains stable during optimization.

Tasks:

- keep current `vpp_bridge_daemon.py`
- document supported actions
- log action timing

Actions currently supported:

- show_version
- show_interfaces
- show_plugins
- show_sessions
- set_interface_state
- run_cli

Good first candidates for typed binary API migration:

- show_version
- show_interfaces
- show_sessions
- set_interface_state
- counters
- thread/runtime stats

Deliverables:

- stable CLI backend
- baseline latency measurements

---

# Phase 1 — Measure Bottlenecks

Goal: identify slowest control-plane operations.

Add timing around:

- Lua request serialization
- UNIX socket communication
- Python dispatch
- vppctl execution
- output parsing

Metrics to collect:

- p50 latency
- p95 latency
- p99 latency

Deliverables:

- benchmark script
- latency report

---

# Phase 2 — Backend Abstraction

Goal: separate daemon transport logic from VPP backend.

New structure:

tools/
  vpp_backend_base.py
  vpp_backend_cli.py
  vpp_backend_vppapi.py

Daemon becomes a router:

Lua → daemon → backend

Deliverables:

- backend interface
- CLI backend isolated

---

# Phase 3 — Implement Binary API Backend

Goal: introduce the first VPP binary API implementation.

Initial actions:

- show_version
- show_interfaces
- show_sessions
- set_interface_state

If the VPP API supports it cleanly in the chosen version:

- interface counters
- worker or thread runtime stats

Keep CLI fallback for unsupported commands.

Deliverables:

tools/vpp_backend_vppapi.py

Success criteria:

- actions work without vppctl
- latency improvement observed

---

# Phase 4 — Hybrid Backend

Goal: combine CLI and binary API safely.

Rules:

typed action → binary API  
unsupported action → CLI fallback

Example:

run_cli → CLI backend

Deliverables:

- hybrid backend
- fallback logic

---

# Phase 5 — Persistent VPP API Session

Goal: avoid reconnect overhead.

Improvements:

- persistent VPP API connection
- automatic reconnection
- request batching
- state reuse across calls

Why it matters:

- avoids repeated setup cost
- supports more frequent polling
- enables tighter experiment control loops
- improves scalability when multiple Lua tasks or front ends are active

Deliverables:

tools/vpp_session_manager.py

Benefits:

- lower latency
- better scalability

Practical lab impact:

- dynamic experiment reconfiguration while MoonGen is running
- frequent polling without brittle CLI parsing
- sub-second control loops
- cleaner automation for future distributed HBR / L4LB work

---

# Phase 6 — Structured JSON Responses

Goal: replace text parsing with structured data.

Current format:

{
  "output": "Name ... up/down ..."
}

Target format:

{
  "interfaces": [
    {
      "name": "local0",
      "index": 0,
      "state": "up"
    }
  ]
}

Deliverables:

- JSON schemas
- typed Lua helpers

---
