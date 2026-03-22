# Documentation Index

This repository contains two kinds of documentation:

- canonical vMoonGen project documentation
- legacy MoonGen reference documentation kept for upstream context

Documentation layout rule:

- `README.md` stays at the repository root
- every other maintained Markdown document lives under `doc/`

If you are working on the VPP integration, host/toolbox runtime, or current lab operations, start with the canonical documents below.

## Canonical Project Docs

- [README.md](../README.md)
  Current project overview and operator quick start.

- [architecture.md](architecture.md)
  Current host/toolbox architecture and component boundaries.

- [control-plane.md](control-plane.md)
  Control-plane request flow, daemon model, and current backend behavior.

- [fast-path.md](fast-path.md)
  VPP/DPDK fast-path model, DAC cross-port rule, and runtime expectations.

- [operations.md](operations.md)
  Standard start, stop, status, and recovery flows.

- [troubleshooting.md](troubleshooting.md)
  Common failure modes and the expected recovery path.

- [vpp-integration.md](vpp-integration.md)
  Lua to daemon to VPP integration details and current contract.

- [roadmap.md](roadmap.md)
  Overall platform roadmap.

- [roadmap-control-plane.md](roadmap-control-plane.md)
  Control-plane optimization roadmap toward the VPP binary API.

## Legacy MoonGen Reference Docs

The documents below are useful as upstream reference, but they are not the source of truth for the current VPP lab integration:

- [packet_api.md](packet_api.md)
- [timestamping.md](timestamping.md)
- [examples.md](examples.md)
- [faq.md](faq.md)
- [install.md](install.md)
- [download.md](download.md)
- [rate_control.md](rate_control.md)

Use those documents for MoonGen mechanics, not for the current vMoonGen operating model.
