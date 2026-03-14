# Recommended project posture

vMoonGen should evolve as a **profile-driven traffic orchestration system**.

## Positioning

- MoonGen provides the scripting and control experience
- VPP provides high-scale packet processing and transport/session execution
- the adapter remains thin and stable

## Recommended posture

### Do
- keep Lua high-level
- define traffic in profiles
- batch control operations
- keep VPP as the owner of TCP/session state
- default to aggregate observability

### Do not
- re-implement TCP in Lua
- put per-flow hot-path logic in the adapter
- make Lua responsible for individual flow lifecycles at scale
- mix DPDK queue ownership between MoonGen and VPP

## Success criteria

The project is successful when:
- users can define large workloads concisely in Lua
- VPP can execute those workloads at high scale
- profile lifecycle and stats are visible and predictable
- backend details stay isolated behind the adapter
