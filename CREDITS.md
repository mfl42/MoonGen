# Credits

## Architecture & Design

**Michel Besnard**
All concepts, architecture, ideas, and technical direction behind vMoonGen.
This project started from 10 years of ideas around network testing —
high-performance traffic generation, DUT monitoring, AI-assisted anomaly detection,
and a clean DSL to drive it all.

## Implementation

Implemented with [Claude](https://claude.ai) (Anthropic) as an AI coding assistant,
working from Michel's specifications, review, and continuous direction.

AI was used as an implementation tool — like a compiler, a framework, or any other
tool in the chain. Authorship of the project belongs to its architect.

## Lab Infrastructure

Hardware investment and lab design by Michel Besnard:
- 3× Minisforum MS-01 (Intel X710 10G SFP+)
- Mikrotik CRS309 / CCR2004 / RB4011
- DAC cabling, VLANs, OOB management network

## Key Technologies

- [VPP / fd.io](https://fd.io) — fast-path forwarding
- [MoonGen / libmoon](https://github.com/emmericp/MoonGen) — packet generation
- [LuaJIT](https://luajit.org) — scenario DSL runtime
- [DPDK](https://dpdk.org) — data plane acceleration
- [AF_XDP](https://www.kernel.org/doc/html/latest/networking/af_xdp.html) — kernel bypass
