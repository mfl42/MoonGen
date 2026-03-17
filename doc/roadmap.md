# vMoonGen Development Roadmap

This roadmap describes the evolution of the **vMoonGen + VPP** integration from an experimental bridge to a repeatable, operable, high-performance lab platform.

---

## Current Status

The following parts are now validated:

- **VPP control-plane reachability** through the CLI socket
- **Persistent bridge daemon** over a UNIX socket
- **LuaJIT control client** calling the daemon successfully
- **MoonGen build** and LuaJIT build on the target host
- **DPDK binding** of the two Intel X710 SFP+ ports with `vfio-pci`
- **Hugepages** and **IOMMU** configuration sufficient for DPDK startup
- **cross-port DAC topology** identified as the required validation path

The remaining dataplane dependency is the **physical SFP+ DAC link** between the two X710 ports.

---

## Architectural Baseline

Current architecture:

    MoonGen / LuaJIT
        |
        +--> front-end experiment driver
        |
        +--> control-plane (Lua -> UNIX socket -> Python daemon -> VPP)

    VPP
        |
        +--> fast-path (DPDK dataplane, TCP/UDP stack, client/server roles across DAC)

The operating split is:

- **FP (Fast-Path)**:
  - VPP dataplane
  - DPDK device ownership
  - transport stack execution
  - cross-port client/server validation through the DAC

- **CP (Control-Plane)**:
  - VPP lifecycle
  - daemon lifecycle
  - VPP CLI/API actions
  - orchestration and observability

---

## Phase 1 — Operationalization

Goal: make the platform easy to start, stop, restart, and debug.

### Objectives

- add operational shell scripts
- add persistent log files for FP and CP
- add status checks
- reduce manual recovery steps after crashes or stale sockets

### Deliverables

- `scripts/start-daemon.sh`
- `scripts/stop-daemon.sh`
- `scripts/status-controlplane.sh`
- `scripts/start-fastpath.sh`
- `scripts/stop-fastpath.sh`
- `scripts/restart-fastpath.sh`
- `scripts/status-fastpath.sh`
- `scripts/restart-lab.sh`

### Logging design

Create a dedicated log tree:

    logs/
      control-plane-actions.log
      control-plane-daemon.log
      fast-path-actions.log
      fast-path-runtime.log

Purpose:

- **actions logs**: explicit operator actions (`start`, `stop`, `restart`, `status`)
- **runtime logs**: stdout/stderr of long-running processes

This phase is now the immediate focus.

---

## Phase 2 — Reliable Local Lab

Goal: make the single-host lab deterministic and repeatable.

### Objectives

- validate DAC-connected dataplane
- validate VPP/DPDK ownership of both X710 ports
- validate client/server split across the two ports
- keep MoonGen-side scripts as auxiliary validation, not as the transport fast path
- document exact bring-up sequence
- document recovery sequence after failed DPDK primary process

### Deliverables

- DAC-validated test procedure
- reproducible lab checklist
- reproducible DPDK source strategy from the `dpdk-stable` GitHub clone
- tested startup order:
  1. render VPP DPDK config
  2. VPP
  3. bridge daemon
  4. optional MoonGen-side workload

### Expected result

The host should reliably support:

- VPP ownership of the two X710 SFP+ ports
- client/server traffic that crosses the DAC
- VPP control actions during active dataplane execution
- repeatable restart of the VPP fast path without reboot

### Build strategy note

The current embedded VPP external dependency flow on `venus` is not yet reliable enough for the DAC dataplane because:

- `build-dpdk` succeeds
- but `install-vpp-native/external/lib/libdpdk.a` is still missing
- rebuild attempts currently fail earlier in the dependency chain when `ipsec-mb` needs `nasm`

The preferred next step is therefore:

1. keep a dedicated `dpdk-stable` source repository on GitHub
2. build and install DPDK from that repository in a controlled build environment
3. expose `libdpdk.pc` through `PKG_CONFIG_PATH`
4. rebuild VPP with `VPP_USE_SYSTEM_DPDK=ON`

That gives the project:

- a pinned DPDK source of truth
- easier containerized builds
- less coupling to the fragile in-tree external install path
- a cleaner path for future NIC qualification beyond the current X710 pair

---

## Phase 3 — Fast Control-Plane Optimization

Goal: improve control latency and make orchestration more scalable.

### Objectives

- keep persistent daemon model
- reduce per-action overhead
- improve error messages
- add typed operations beyond raw `run_cli`

### Candidate improvements

- structured JSON responses for typed actions
- retries for transient socket failures
- state checks before interface actions
- optional caching for stable queries (`show_plugins`, version)

### Future direction

Replace CLI-centric backend calls gradually with the **VPP binary API** for typed operations.

---

## Phase 4 — High-Performance Fast-Path

Goal: stabilize the VPP/DPDK dataplane for high-speed lab use.

### Objectives

- validate 10 Gb/s loop tests
- validate VPP worker layout
- define CPU/core placement
- document line-rate and latency test recipes across the DAC

### Candidate tests

- VPP client on port 0 and server on port 1
- VPP client on port 1 and server on port 0
- MoonGen-side auxiliary validation only where it does not steal the VPP DPDK ports

### Design rule

Control-plane calls must remain **outside** the packet hot path.

---

## Phase 5 — Integrated FP/CP Orchestration

Goal: make MoonGen and VPP act as one coherent lab platform.

### Objectives

- FP/CP start and stop workflows
- standard experiment entrypoints
- control-plane observability while traffic is running
- clean shutdown and restart semantics

### Deliverables

- standard “lab start” command
- standard “lab status” command
- standard “lab restart” command
- synchronized log files for FP and CP

---

## Phase 6 — Distributed and Research Extensions

Goal: evolve from single-host lab to multi-node orchestration if needed.

### Possible future work

- node-local agents
- central coordinator
- experiment metadata
- result collection
- repeatable benchmark suites
- MoonGen + VPP + multi-node automation

---

## Operations Notes

### Control-Plane startup order

1. VPP process must be running and listening on `cli.sock`
2. bridge daemon must be started
3. LuaJIT or MoonGen control clients may connect

### Fast-Path startup order

1. DPDK devices bound to `vfio-pci`
2. hugepages mounted and available
3. VPP launched with DPDK enabled on both X710 ports
4. physical DAC link up
5. client and server roles split across the two ports

### Common failure modes

- stale `cli.sock` -> VPP not listening
- stale `/tmp/vmoongen.sock` -> daemon not running
- devices present but no traffic -> physical link absent or down
- no transport validation -> client/server accidentally placed on the same port

---

## Summary

The project now has a validated control-plane and a VPP/DPDK-oriented dataplane model.

The immediate next milestone is:

**Operate the lab through scripts with logs, then validate the VPP/DPDK DAC-based fast-path with strict cross-port roles.**
