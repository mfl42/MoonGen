# vMoonGen Development Roadmap

This document describes the technical roadmap for the vMoonGen + VPP integration.

The goal is to transform the current experimental bridge into a high-performance orchestration layer between MoonGen and FD.io VPP.

---

# Current State

The current architecture works as follows:

MoonGen (Lua)
→ lua/vpp.lua
→ tools/vpp_contract_bridge.py
→ tools/vpp_backend_vpp.py
→ VPP CLI (vppctl via CLI socket)

Lua calls spawn a Python process which executes a VPP CLI command.

This architecture validates functionality but introduces overhead due to:

- Python interpreter startup
- repeated module loading
- shell invocation
- CLI command execution

This is acceptable for experimentation but not ideal for high-frequency orchestration.

---

# Development Goals

The vMoonGen project aims to achieve:

- efficient orchestration of VPP from Lua
- low-latency control plane
- compatibility with MoonGen scripting
- support for dynamic traffic experiments
- maintainability and extensibility

---

# Phase 1 — Control Plane Optimization

The first optimization step focuses on removing repeated process creation.

## Persistent Bridge Daemon

Replace the current per-call bridge with a persistent daemon.

New architecture:

MoonGen (Lua)
→ UNIX socket
→ Python bridge daemon
→ VPP backend
→ VPP

Benefits:

- no Python startup per request
- faster control operations
- simpler error handling
- easier debugging

## Bridge Daemon Responsibilities

The daemon should:

- listen on a UNIX domain socket
- receive JSON requests
- dispatch actions to the backend
- return JSON responses

Example socket:

    /tmp/vmoongen.sock

Example request:

    {
      "version": 1,
      "action": "show_version",
      "payload": {
        "socket_path": "/home/user/Projects/vpp/run/cli.sock"
      }
    }

## Lua Client Module

A new Lua module will replace the current io.popen implementation.

Example module:

    lua/vpp_socket.lua

Example usage:

    local vpp = require("vpp_socket")

    local socket = "/home/user/Projects/vpp/run/cli.sock"

    print(vpp.show_version(socket))

---

# Phase 2 — Backend Improvements

Once the persistent daemon exists, the backend can be improved.

## Persistent CLI Interaction

Instead of executing vppctl for every request:

- reuse a CLI session
- avoid repeated process creation

Benefits:

- lower latency
- faster command execution

## Binary API Integration

The long-term objective is to replace CLI calls with the VPP Binary API.

Advantages:

- structured responses
- better error handling
- higher performance
- full VPP feature access

The CLI interface should remain available for debugging and exploration.

---

# Phase 3 — MoonGen Integration Improvements

Once the control plane is optimized, improvements can focus on Lua and MoonGen.

## Separation of Control and Data Plane

MoonGen scripts should clearly separate:

Control Plane:
- VPP configuration
- interface control
- session management

Data Plane:
- packet generation
- packet processing
- traffic measurements

The control plane must not run inside packet generation loops.

## High-Level Lua API

Introduce higher-level orchestration functions.

Examples:

- vpp.start_profile()
- vpp.stop_profile()
- vpp.configure_interface()
- vpp.create_session()

This will simplify MoonGen experiment scripts.

---

# Phase 4 — Experimentation Framework

Once the integration stabilizes, vMoonGen can evolve into a research framework.

Possible features:

- traffic scenario automation
- experiment reproducibility
- benchmark orchestration
- multi-node experiments

---

# Phase 5 — Future Research Directions

Potential future work includes:

- VPP session-scale experiments (millions of flows)
- automated benchmarking pipelines
- MoonGen ↔ VPP traffic orchestration
- real-time traffic feedback loops
- integration with network emulation environments

---

# Summary

The roadmap consists of five main phases:

1. Control-plane optimization (persistent bridge daemon)
2. Backend improvements (persistent CLI, binary API)
3. MoonGen integration improvements
4. Experimentation framework
5. Future research extensions

The immediate priority is Phase 1: Persistent bridge daemon.

This will significantly improve responsiveness and scalability of the integration.
