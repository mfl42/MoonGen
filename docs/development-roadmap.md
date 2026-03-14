# Development roadmap

## Phase 1

Basic architecture

- Lua profile API
- mock adapter
- JSON contract

## Phase 2

Adapter improvements

- contract parser
- backend abstraction
- mock backend module

## Phase 3

Real backend

- integrate VPP API client
- install profiles in VPP
- worker sharding

## Phase 4

Performance

- high CPS ramp control
- session scheduler
- aggregated statistics

## Phase 5

Advanced features

- sampled flow tracing
- latency metrics
- distributed control

## Phase: VPP backend bootstrap

First real backend capability:

- detect VPP API socket
- validate connectivity
- report backend status

This establishes the control channel before implementing profile installation.
