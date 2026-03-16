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
- **MoonGen device discovery** showing 2 usable DPDK devices

The remaining dataplane dependency is the **physical SFP+ DAC link** between the two X710 ports.

---

## Architectural Baseline

Current architecture:

    MoonGen / LuaJIT
        |
        +--> fast-path (DPDK dataplane, worker threads)
        |
        +--> control-plane (Lua -> UNIX socket -> Python daemon -> VPP)

The operating split is:

- **FP (Fast-Path)**:
  - MoonGen dataplane
  - DPDK device ownership
  - packet generation / receive / latency / throughput

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
- validate MoonGen L2/L3 latency tests
- validate `vpp_multithread_control.lua`
- document exact bring-up sequence
- document recovery sequence after failed DPDK primary process

### Deliverables

- DAC-validated test procedure
- reproducible lab checklist
- tested startup order:
  1. VPP
  2. bridge daemon
  3. MoonGen fast-path

### Expected result

The host should reliably support:

- MoonGen TX/RX on the two X710 SFP+ ports
- VPP control actions during active dataplane execution
- repeatable restart of dataplane without reboot

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

Goal: stabilize the MoonGen dataplane for high-speed lab use.

### Objectives

- validate 10 Gb/s loop tests
- validate multi-threaded worker layout
- define CPU/core placement
- document line-rate and latency test recipes

### Candidate tests

- `examples/l2-load-latency.lua 0 1`
- `examples/l3-load-latency.lua 0 1`
- `examples/vpp_multithread_control.lua 0`

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
3. MoonGen launched as root
4. physical link up for dataplane traffic

### Common failure modes

- stale `cli.sock` -> VPP not listening
- stale `/tmp/vmoongen.sock` -> daemon not running
- stale `/var/run/dpdk/rte/config` -> previous MoonGen primary process still alive
- devices present but no traffic -> physical link absent or down

---

## Summary

The project now has a validated control-plane and a nearly ready dataplane.

The immediate next milestone is:

**Operate the lab through scripts with logs, then validate the DAC-based fast-path.**
