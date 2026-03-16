MoonGen is basically a Lua wrapper around DPDK with utility functions for packet generation. Users write custom scripts for their experiments. It is recommended to make use of hard-coded setup-specific constants in your scripts. The script is the configuration, it is beside the point to write a complicated configuration interface for a script.

The following diagram shows the architecture and how multi-core support is handled.

<p align="center">
<img alt="Architecture" src="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png" srcset="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png 1x, https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture@2x.png 2x"/>
</p>

Execution begins in the master task that must be defined in the user's script. This task configures queues and filters on the used NICs and then starts one or more slave tasks.

Note that Lua does not have any native support for multi threading. MoonGen therefore starts a new and completely independent LuaJIT VM for each thread. The new VMs receive serialized arguments: the function to execute and arguments like the queue to send packets from. Threads only share state through the underlying library.

The example script quality-of-service-test.lua shows how this threading model can be used to implement a typical load generation task. It implements a QoS test by sending two different types of packets and measures their throughput and latency. It does so by starting two packet generation tasks: one for the background traffic and one for the prioritized traffic. A third task is used to categorize and count the incoming packets.

# vMoonGen Lab Roadmap

This document describes the evolution of the **vMoonGen experimentation lab**.

The objective is to build a **reproducible, automated dataplane experimentation environment**
based on:

- MoonGen / DPDK
- VPP
- a lightweight control-plane bridge
- automation scripts

---

# Project Goals

The lab aims to provide:

- reproducible dataplane experiments
- automated lab lifecycle
- clean CP / FP separation
- high-performance packet generation
- simple orchestration for experiments

---

# Architecture Model

The system is divided into two main layers.

## Control Plane (CP)

Responsibilities:

- configure VPP
- inspect dataplane state
- orchestrate experiments
- provide automation interfaces

Components:

Lua client  
↓  
UNIX socket  
↓  
vpp_bridge_daemon  
↓  
VPP control interface

Runtime:

systemd --user

---

## Fast Path (FP)

Responsibilities:

- packet generation
- latency measurement
- throughput testing

Component:

MoonGen

Runtime:

tmux session

MoonGen uses:

DPDK

---

# Runtime Model

The lab runtime is organized as follows.

| Component | Runtime |
|----------|--------|
| VPP | tmux |
| MoonGen | tmux |
| bridge daemon | systemd --user |
| scripts | shell |
| logs | files + journalctl |

---

# Lab Control Interface

The lab is controlled through:

scripts/vmoongenctl

Examples:

vmoongenctl start-lab  
vmoongenctl stop-lab  
vmoongenctl status-cp  
vmoongenctl status-fp  

This interface orchestrates:

- VPP startup
- daemon lifecycle
- fast-path execution
- diagnostics

---

# Phase 1 — Lab Stabilization

Goal:

Create a reproducible environment.

Tasks:

- host preparation scripts
- NIC binding automation
- hugepages setup
- environment validation

Scripts:

setup-host.sh  
check-lab.sh  
check-nics.sh  
dpdk-reset.sh  

Status:

✓ completed

---

# Phase 2 — Automation

Goal:

Provide simple control of the lab lifecycle.

Tasks:

- start / stop scripts
- status checks
- fast-path management

Scripts:

start-lab.sh  
stop-lab.sh  
start-fastpath.sh  
restart-fastpath.sh  

Status:

✓ completed

---

# Phase 3 — Lab Control Interface

Goal:

Provide a unified operator interface.

Component:

scripts/vmoongenctl

Features:

- lab lifecycle commands
- control-plane status
- fast-path control
- diagnostic access

Status:

✓ completed

---

# Phase 4 — Documentation

Goal:

make the lab understandable and reproducible.

Documents:

README.md  
architecture.md  
roadmap.md  
roadmap-control-plane.md  

Content:

- architecture explanation
- DAC test procedure
- troubleshooting guide
- automation documentation

Status:

✓ ongoing

---

# Phase 5 — Control Plane Optimization

Goal:

remove dependency on CLI parsing.

Current model:

Lua  
→ daemon  
→ vppctl  
→ CLI socket  
→ text output  

Target model:

Lua  
→ daemon  
→ VPP binary API  
→ structured responses  

Benefits:

- faster control operations
- structured data
- no fragile text parsing

Tasks:

- backend abstraction
- binary API backend
- persistent VPP session
- CLI fallback support

Status:

planned

---

# Phase 6 — Observability

Goal:

improve visibility of experiments.

Add:

- structured logs
- latency measurements
- experiment traces

Possible tools:

- Prometheus
- Grafana
- VPP telemetry

Status:

planned

---

# Phase 7 — Experiment Framework

Goal:

enable repeatable experiments.

Features:

- scenario definitions
- experiment automation
- result collection

Possible structure:

experiments/
  latency/
  throughput/
  qos/

Status:

planned

---

# Phase 8 — Performance Benchmarking

Goal:

benchmark VPP under controlled load.

Experiments:

- latency distribution
- throughput limits
- queue behavior
- packet loss analysis

Tools:

- MoonGen
- VPP counters
- NIC hardware statistics

Status:

planned

---

# Phase 9 — Advanced Control Plane

Future improvements:

- full VPP binary API integration
- batch control operations
- experiment orchestration APIs
- experiment dashboards

Status:

future work

---

# Long-Term Vision

The vMoonGen lab becomes a platform for:

- dataplane experimentation
- networking research
- automated benchmarking
- reproducible packet processing tests
