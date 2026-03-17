# vMoonGen Architecture

vMoonGen combines MoonGen, LuaJIT, VPP, and a thin Python daemon into a lab for high-rate transport and dataplane experimentation.

## Design Goals

- keep the transport fast path inside VPP + DPDK
- keep control logic lightweight and scriptable from Lua
- make host preparation repeatable
- preserve enough flexibility to move toward a distributed architecture later

## Current Deployment Model

Current deployment is organized around a host/toolbox split.

### Host Responsibilities

- hugepages
- VFIO modules
- binding the Intel X710 ports to `vfio-pci`
- VPP container lifecycle
- access to the physical 10G interfaces

### Toolbox Responsibilities

- `scripts/vmoongenctl`
- `tools/vpp_bridge_daemon.py`
- MoonGen-side experiment driving
- Lua control clients
- logs and diagnostics

## Current Component Graph

```text
+----------------------+
|       Toolbox        |
|----------------------|
| vmoongenctl          |
| start/stop/status    |
| vpp_bridge_daemon    |
| MoonGen front-end    |
| logs                 |
+----------+-----------+
           |
           | /tmp/vmoongen.sock
           |
+----------v-----------+
|     Python daemon    |
|----------------------|
| request dispatch     |
| backend selection    |
+----------+-----------+
           |
           | vppctl today
           | vppapi later
           |
+----------v-----------+
|         VPP          |
|----------------------|
| fast path +          |
| TCP/UDP stack        |
+----------+-----------+
           |
           | DPDK device ownership
           |
+----------v-----------+
| Intel X710 port pair |
+----------------------+
```

## Control-Plane Flow

Current request path:

```text
Lua
  -> UNIX socket client
  -> Python daemon
  -> VPP backend
  -> vppctl over cli.sock
  -> structured JSON response
```

The Lua side is intentionally thin. It should remain a compact control client, not a second heavyweight control stack.

## Fast-Path Flow

Target fast-path:

```text
client role on one X710 port
  -> DAC
  -> server role on the other X710 port
  -> VPP session / transport stack
```

The VPP process owns the DPDK ports in the intended architecture.

MoonGen remains useful as a front-end driver for:

- scenario control
- orchestration
- experiment automation
- optional traffic-side validation scripts

The key rule for the DAC lab is:

```text
port 0 <-> DAC <-> port 1
```

Not:

```text
client and server on the same port
```

Historical repository examples still include MoonGen dataplane scripts, but they are not the architectural source of truth for the target VPP fast path.

## MoonGen-Side Workload

The current default MoonGen-side workload script is:

```text
examples/vpp_multithread_control.lua
```

It is best treated as:

- a front-end validation workload
- a control-plane exercise
- an integration aid while the VPP fast path evolves

It should not be confused with the intended VPP/DPDK transport fast path itself.

## Current Runtime Choice on venus

The intended target on `venus` is:

- VPP in a podman container
- DPDK enabled on both X710 ports
- DAC traversal between ports
- control-plane daemon on the toolbox side

This repository now includes a helper to render a DPDK-enabled VPP session config for that topology:

```text
scripts/render-vpp-session-conf.sh
```

The current config rendered by that helper reserves:

- `0000:02:00.0`
- `0000:02:00.1`

for VPP.

## Near-Term Architecture Direction

The immediate next architecture step is:

- stabilize the VPP/DPDK fast path across the DAC pair
- keep MoonGen and Lua as front-end experiment drivers
- improve the daemon/backend path toward the VPP binary API

## Long-Term Direction

The longer-term target is a distributed system with:

- host-based routers at the front
- optional L4 load-balancing functions
- stateful back ends
- MoonGen injectors as one class of service module among others

That future work should build on the same principle:

- VPP owns the transport fast path
- control and orchestration stay lightweight and automatable
- traffic must traverse a real path between roles
