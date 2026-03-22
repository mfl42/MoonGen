# Control Plane

The vMoonGen control plane is a lightweight orchestration layer between Lua scripts and VPP.

## Current Request Path

```text
Lua
  -> lua/vpp.lua
  -> lua/vpp_socket.lua
  -> /tmp/vmoongen.sock
  -> tools/vpp_bridge_daemon.py
  -> tools/vpp_backend_vpp.py
  -> vppctl -s <cli.sock>
  -> JSON response
```

## Why This Exists

The project does not want heavy control logic inside MoonGen scripts.

The daemon provides:

- a stable UNIX socket endpoint
- centralized backend selection
- structured request and response handling
- a migration point toward the VPP binary API

## Current Supported Actions

Current typed actions include:

- `show_version`
- `show_interfaces`
- `show_plugins`
- `show_sessions`
- `set_interface_state`
- `run_cli`

The Lua wrappers live in:

- [lua/vpp.lua](../lua/vpp.lua)
- [lua/vpp_socket.lua](../lua/vpp_socket.lua)

The daemon lives in:

- [tools/vpp_bridge_daemon.py](../tools/vpp_bridge_daemon.py)

The current VPP backend lives in:

- [tools/vpp_backend_vpp.py](../tools/vpp_backend_vpp.py)

## Response Model

Responses are structured JSON payloads.

Example:

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

## Current Limitations

- the backend still relies on `vppctl`
- most payloads are still plain text in the `output` field
- there is no persistent VPP binary API session yet

## Next Control-Plane Step

The next major control-plane improvement is:

```text
Lua -> daemon -> VPP binary API -> structured response
```

The daemon should remain the stable abstraction boundary even after the backend changes.
