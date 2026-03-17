# VPP Integration

This document describes the current vMoonGen integration path between Lua, the Python daemon, and VPP.

## Purpose

The project needs a control-plane path that is:

- lightweight
- scriptable from Lua
- easy to automate
- ready to migrate toward the VPP binary API

The current solution is a persistent UNIX socket daemon that forwards typed actions to a VPP backend.

## Current Component Layout

Lua-side entrypoints:

- [lua/vpp.lua](../lua/vpp.lua)
- [lua/vpp_socket.lua](../lua/vpp_socket.lua)

Daemon:

- [tools/vpp_bridge_daemon.py](../tools/vpp_bridge_daemon.py)

Current VPP backend:

- [tools/vpp_backend_vpp.py](../tools/vpp_backend_vpp.py)

Environment helpers:

- [lua/vmoongen-env.lua](../lua/vmoongen-env.lua)
- [tools/vmoongen_env.py](../tools/vmoongen_env.py)

## Current Request Flow

```text
Lua caller
  -> vpp_socket.lua
  -> /tmp/vmoongen.sock
  -> vpp_bridge_daemon.py
  -> VPPBackend
  -> vppctl -s <cli.sock>
  -> JSON response
```

Current default sockets:

- daemon socket: `/tmp/vmoongen.sock`
- VPP CLI socket: `<VPP_ROOT>/run/cli.sock`

## Current Supported Operations

The current typed operations are:

- `show_version`
- `show_interfaces`
- `show_plugins`
- `show_sessions`
- `set_interface_state`
- `run_cli`

`show_sessions` now defaults to the lighter `summary` mode, with `verbose` available explicitly when needed.

## Current Contract

Example request:

```json
{
  "version": 1,
  "action": "show_version",
  "payload": {
    "socket_path": "/home/mfl42/Projects/vpp/run/cli.sock"
  }
}
```

Example response:

```json
{
  "ok": true,
  "version": 1,
  "data": {
    "backend": "vpp",
    "socket_path": "/home/mfl42/Projects/vpp/run/cli.sock",
    "output": "vpp v26.06-rc0 ..."
  }
}
```

## Why the Daemon Matters

The daemon gives the project a stable abstraction boundary.

That matters because the backend can evolve from:

```text
daemon -> vppctl
```

to:

```text
daemon -> VPP binary API
```

without changing every Lua caller or every operational script.

## Current Limitations

- backend still uses `vppctl`
- most results are still text in the `output` field
- no persistent VPP binary API session yet
- some orchestration still assumes a local single-host lab

## Next Integration Step

The next step is not to remove the daemon.

It is to keep the daemon and swap the backend progressively:

- typed actions first
- CLI fallback where needed
- structured JSON payloads instead of text parsing

## Build Note For The VPP Dataplane

For the dataplane itself, the preferred direction is now to decouple DPDK sourcing from the current fragile VPP external dependency flow.

The intended model is:

```text
dpdk-stable GitHub clone
  -> reproducible DPDK build/install
  -> libdpdk.pc + headers
  -> VPP rebuild with VPP_USE_SYSTEM_DPDK=ON
```

This is especially relevant on `venus`, where:

- DPDK object build artifacts already exist
- but the external install tree is incomplete
- and the in-tree rebuild path is currently blocked by missing `nasm`
