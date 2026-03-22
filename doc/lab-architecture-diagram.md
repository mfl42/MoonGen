# Lab Architecture Diagram

_Last updated: 2026-03-17_

This document provides a GitHub-rendered overview of the current vMoonGen lab using Mermaid diagrams.

## 1. Full Lab Architecture

```mermaid
flowchart TD
    U["User / Operator"] --> CTL["scripts/vmoongenctl"]

    subgraph TOOLBOX["Toolbox"]
        CTL --> SCRIPTS["shell orchestration"]
        LUA["Lua control client"] --> SOCK["UNIX socket"]
        SOCK --> DAEMON["vpp_bridge_daemon.py"]
        MG["MoonGen front-end<br/>injector / driver"]
        LOGS["logs/"]
    end

    subgraph HOST["Host / Fast Path"]
        VPP["VPP + DPDK<br/>fast path + TCP/UDP stack"]
        NIC0["Intel X710 Port 0"]
        NIC1["Intel X710 Port 1"]
    end

    DAEMON --> VPP
    VPP --> NIC0
    NIC1 --> VPP
    NIC0 --> DAC["SFP+ DAC"]
    DAC --> NIC1
    MG -. scenario driving .-> DAEMON
    LOGS -. observability .-> DAEMON
    LOGS -. observability .-> VPP
```

## 2. Runtime Model

```mermaid
flowchart LR
    subgraph HOST["Host"]
        VPP["VPP container"]
        PREP["hugepages + vfio-pci"]
    end

    subgraph TOOLBOX["Toolbox"]
        DAEMON["CP daemon"]
        MG["MoonGen-side workload"]
        CTL["vmoongenctl"]
    end

    PREP --> VPP
    CTL --> DAEMON
    CTL --> MG
    CTL --> VPP
```

## 3. Control Plane Request Flow

```mermaid
sequenceDiagram
    participant Lua as Lua client
    participant Sock as UNIX socket
    participant Daemon as vpp_bridge_daemon.py
    participant Backend as VPP backend
    participant VPP as VPP

    Lua->>Sock: JSON request
    Sock->>Daemon: action + payload
    Daemon->>Backend: dispatch action
    Backend->>VPP: CLI today / Binary API later
    VPP-->>Backend: state / result
    Backend-->>Daemon: structured response
    Daemon-->>Sock: JSON response
    Sock-->>Lua: response
```

## 4. Current vs Target Control Plane

```mermaid
flowchart TB
    subgraph CURRENT["Current model"]
        A1["Lua"] --> A2["UNIX socket"]
        A2 --> A3["Python daemon"]
        A3 --> A4["vppctl / CLI socket"]
        A4 --> A5["Text output + parsing"]
    end

    subgraph TARGET["Target model"]
        B1["Lua"] --> B2["UNIX socket"]
        B2 --> B3["Python daemon"]
        B3 --> B4["Persistent VPP Binary API session"]
        B4 --> B5["Structured response"]
    end
```

## 5. DAC Cross-Port Rule

```mermaid
flowchart LR
    C0["Client role on port 0"] --> P0["X710 Port 0"]
    P0 --> DAC["SFP+ DAC"]
    DAC --> P1["X710 Port 1"]
    P1 --> S1["Server role on port 1"]
```

The reverse direction is equally valid:

```mermaid
flowchart LR
    C1["Client role on port 1"] --> P1["X710 Port 1"]
    P1 --> DAC["SFP+ DAC"]
    DAC --> P0["X710 Port 0"]
    P0 --> S0["Server role on port 0"]
```

Forbidden validation model:

```text
client and server on the same physical port
```

## 6. Typical Start Sequence

```mermaid
sequenceDiagram
    participant User
    participant Prep as scripts/setup-host.sh
    participant Render as scripts/render-vpp-session-conf.sh
    participant VPP as scripts/start-vpp-host.sh
    participant Daemon as scripts/vmoongenctl start-lab
    participant MG as scripts/vmoongenctl start-fp

    User->>Prep: prepare host
    User->>Render: render VPP DPDK config
    User->>VPP: start VPP container
    User->>Daemon: start control plane
    User->>MG: optional MoonGen-side workload
```

## 7. Component Responsibilities

| Component | Responsibility |
| --- | --- |
| VPP + DPDK | transport fast path and packet processing |
| Intel X710 pair | physical dataplane interfaces |
| SFP+ DAC | required cross-port validation path |
| MoonGen / LuaJIT | front-end experiment driving and auxiliary validation |
| `vpp_bridge_daemon.py` | control-plane bridge |
| `vmoongenctl` | unified lab control interface |
| shell scripts | lifecycle automation |
| logs | observability |
