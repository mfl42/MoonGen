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

### Roadmap Status (2026-03-19)

Completed:

- Lua DSL parser/compiler and worker-plan generation
- deterministic runtime skeleton (`run`, `replay`, `campaign`)
- one-shot smoke workflow (`scenario-smoke`) local + venus
- explicit `1-arm` / `2-arm` scenario modes in DSL
- explicit arm-role model (`topology.arms`) with cross-arm validation
- worker role assignment (`client` / `server`) and arm assignment (`left` / `right`)

In progress:

- unify branch publishing flow between mac and venus
- connect deterministic runtime outputs to real VPP dataplane measurements

Not started:

- true stateful server behavior at runtime (beyond deterministic skeleton)
- SCTP descriptor and execution path
- topology import from BreakingPoint / external artifacts

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

That recipe is now implemented in the repository through the build container and the `build-vpp-system-dpdk` workflow. The next remaining work is validation on `venus` and then the first successful DAC dataplane bring-up with the rebuilt VPP package.

That gives the project:

- a pinned DPDK source of truth
- easier containerized builds
- less coupling to the fragile in-tree external install path
- a cleaner path for future NIC qualification beyond the current X710 pair

### Future NIC Strategy

The hardware path is now split deliberately:

- keep the Intel X710 2x10G DAC pair as the permanent light baseline
- qualify a 25G class adapter that fits the MS-01 comfortably
- qualify a 100G class adapter only if the compact chassis remains thermally sane
- move to the larger AMD Genoa server target if RAM density, thermals, or sustained 100G pressure exceed what the MS-01 can deliver cleanly

Current preferred order:

1. Intel E830-XXVDA2 as the best next MS-01 upgrade for dual-port 25G
2. Intel E810-CQDA1 as the first serious single-port 100G experiment
3. NVIDIA ConnectX-6 Dx only after explicit cooling validation
4. avoid BlueField-2 100G and BlueField-3 as the primary MS-01 path

This strategy also keeps a clean rollback path:

- validate experimental NICs
- return to the light X710 2x10G configuration for day-to-day work

See [hardware-strategy.md](hardware-strategy.md) for the qualification matrix, cooling notes, DPU/AI guidance, and the 5-day PoC validation track.

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
- scenario lifecycle actions for `target`, `ramp`, `steady`, and `finish`
- result objects that can seed the next adaptive benchmark run

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
- 25G and 100G variants using the same cross-port role rule, first on compact nodes and then on the larger server path if needed
- `1-arm` client simulation against real servers using superflows
- generic firewall L4 benchmarks:
  - max bandwidth UDP IPv4
  - max connections per second TCP IPv4
  - max concurrent sessions based on 50% of max TCP CPS

### Search strategy

The benchmark controller should converge using a dichotomy-style search around the acceptable operating point rather than only linear sweeps.

Default acceptance ideas:

- `0` drop rate unless the scenario says otherwise
- acceptable mean or percentile latency
- up to `3` TCP retries during setup

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
- scenario engine for `1-arm` and `2-arm` modes
- superflow profiles
- adaptive phase timing

---

## Client/Server Feature Priorities

### P0 / mandatory

- enforce cross-arm traffic model for `2-arm` (no same-arm client/server shortcut)
- represent arm roles explicitly in scenario (`left_role`, `right_role`)
- support `1-arm` client simulation against real servers (`right_role=real-server`)
- persist worker role+arm in worker-plan exports
- keep deterministic `run/replay/campaign` path green on local and venus

### P1 / nice to have

- explicit role-aware rate split knobs (`client_cps_share`, `server_cps_share`)
- directional metrics per arm and per role in runtime exports
- scenario wizard fields for role mapping and duplex mode
- prebuilt scenario templates (`2-arm client->server`, `2-arm full-duplex`, `1-arm superflow`)

### P2 / long term roadmap

- full client/server behavior library (HTTP profiles, DNS-like, custom app models)
- SCTP scenario model and execution backend
- external topology/profile import (BreakingPoint, multi-VLAN, VRF)
- adaptive controller using previous run artifacts for auto-tuned phases
- scenario wizard for Lua/DSL generation
- topology converter path with staged support for VLAN, VRF, SR-IOV hints, IPv6, and SCTP descriptors
- stable artifact schemas for `run-summary`, `phase-summary`, `failure-window`, and `campaign-results`
- structured benchmark results

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
- import/conversion path from Ixia BreakingPoint topology and profile artifacts

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
