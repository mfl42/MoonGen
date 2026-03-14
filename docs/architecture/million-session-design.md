# Million-session TCP design

vMoonGen targets million-scale synthetic TCP sessions by using:

- MoonGen as the **control-plane profile engine**
- VPP as the **dataplane and TCP/session engine**
- a thin adapter as the **session orchestration and observability layer**

## Core principles

1. VPP owns packet I/O and TCP state
2. Sessions are sharded by worker
3. Lua defines profiles, not individual flows
4. Control is batch-oriented
5. Stats are aggregated by default

## Recommended project posture

### MoonGen
MoonGen is the orchestration plane.

Responsibilities:
- load Lua profiles
- validate profile definitions
- compile profiles into session plans
- send batch commands to the adapter
- poll aggregate stats
- render human-friendly progress and metrics

MoonGen should not:
- own TCP state
- transmit per-flow packets directly for VPP-backed traffic
- manage retransmissions, congestion control, or per-packet timers

### VPP
VPP is the dataplane and transport/session engine.

Responsibilities:
- own worker threads
- own packet I/O
- own TCP state machine
- own timers and flow/session state
- own scale-out across workers

VPP should not:
- expose a per-packet scripting model to Lua
- depend on MoonGen for transport correctness

### Thin adapter
The adapter is the bridge between MoonGen profiles and VPP execution.

Responsibilities:
- encode profile requests
- install, start, stop, and remove profiles
- translate stats and health signals
- keep the control path small and stable

The adapter should remain thin:
- no TCP logic
- no packet scheduling logic in the hot path
- no per-flow ownership outside VPP

## Control plane vs dataplane

```text
Lua profile
   |
   v
MoonGen control API
   |
   v
Profile compiler / planner
   |
   v
Thin adapter
   |
   v
VPP workers + session engine + TCP stack
   |
   v
NIC
