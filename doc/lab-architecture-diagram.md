# Lab Architecture Diagram

_Last updated: 2026-03-16_

This document provides a GitHub-rendered overview of the vMoonGen lab using **Mermaid** diagrams.

---

## 1. Full Lab Architecture

```mermaid
flowchart TD
    U["User / Operator"] --> CTL["scripts/vmoongenctl"]

    subgraph CP["Control Plane (CP)"]
        CTL --> SCRIPTS["FP/CP shell scripts"]
        LUA["Lua control client"] --> SOCK["UNIX socket"]
        SOCK --> DAEMON["vpp_bridge_daemon.py"]
        DAEMON --> VPPAPI["VPP control interface<br/>CLI today / Binary API later"]
    end

    subgraph DP["Dataplane / Fast Path (FP)"]
        MG["MoonGen / LuaJIT"] --> DPDK["DPDK"]
        DPDK --> NIC0["Intel X710 Port 0"]
        NIC1["Intel X710 Port 1"] --> DPDK
    end

    VPPAPI --> VPP["VPP"]
    NIC0 --> DAC["SFP+ DAC loopback"]
    DAC --> NIC1

    VPP --> NIC0
    NIC1 --> VPP

    LOGS["logs/ + journalctl"] -. observability .-> DAEMON
    LOGS -. observability .-> MG
    LOGS -. observability .-> VPP

2. Runtime Model

flowchart LR
    subgraph TMUX["tmux"]
        VPP["VPP process"]
        MG["MoonGen fast-path"]
    end

    subgraph SYSTEMD["systemd --user"]
        DAEMON["vpp_bridge_daemon.py"]
    end

    subgraph SHELL["Shell scripts"]
        VMGCTL["vmoongenctl"]
        START["start-lab.sh"]
        STOP["stop-lab.sh"]
        CHECK["check-lab.sh"]
    end

    VMGCTL --> START
    VMGCTL --> STOP
    VMGCTL --> CHECK
    START --> VPP
    START --> DAEMON
    START --> MG

3. Control Plane Request Flow

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

4. Current vs Target Control Plane

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

5. Fast Path Dataplane Flow

flowchart LR
    TX["MoonGen TX worker"] --> Q0["DPDK TX queue"]
    Q0 --> P0["X710 Port 0"]
    P0 --> DAC["SFP+ DAC cable"]
    DAC --> P1["X710 Port 1"]
    P1 --> Q1["DPDK RX queue"]
    Q1 --> RX["MoonGen RX worker"]

6. Typical Start Sequence

sequenceDiagram
    participant User
    participant Scripts as scripts/start-lab.sh
    participant VPP
    participant Daemon
    participant MoonGen

    User->>Scripts: start-lab.sh
    Scripts->>Scripts: setup-host.sh
    Scripts->>Scripts: dpdk-reset.sh
    Scripts->>VPP: start
    Scripts->>Daemon: start
    Scripts->>Scripts: check-lab.sh
    User->>MoonGen: start-fastpath.sh

7. Typical Stop Sequence

sequenceDiagram
    participant User
    participant Scripts as scripts/stop-lab.sh
    participant MoonGen
    participant Daemon
    participant VPP

    User->>Scripts: stop-lab.sh
    Scripts->>MoonGen: stop
    Scripts->>Daemon: stop
    Scripts->>VPP: stop
    Scripts->>Scripts: cleanup DPDK runtime

sequenceDiagram
    participant User
    participant Scripts as scripts/stop-lab.sh
    participant MoonGen
    participant Daemon
    participant VPP

    User->>Scripts: stop-lab.sh
    Scripts->>MoonGen: stop
    Scripts->>Daemon: stop
    Scripts->>VPP: stop
    Scripts->>Scripts: cleanup DPDK runtime

8. Component Responsibilities

Component
Responsibility
MoonGen
high-speed packet generation and measurement
DPDK
direct NIC access and queue management
Intel X710
physical dataplane interfaces
SFP+ DAC
local loop for dataplane validation
VPP
packet processing dataplane
vpp_bridge_daemon.py
control-plane bridge
vmoongenctl
unified lab control interface
shell scripts
lifecycle automation
tmux
interactive runtime for VPP and MoonGen
systemd –user
supervised daemon lifecycle
logs + journalctl
observability

9. Notes
•FP (Fast Path) = MoonGen + DPDK + NIC dataplane
•CP (Control Plane) = Lua control + daemon + VPP management
•Current control-plane backend is CLI-oriented
•Next optimization step is a persistent VPP binary API backend
