# Scenario Model

This document defines the target traffic model for vMoonGen as an application simulator and DUT benchmark platform.

## Product Modes

vMoonGen is expected to support two primary traffic-generation modes.

### 2-arm mode

This is the full application simulator mode.

Intent:

- simulate clients on one arm
- simulate servers on the opposite arm
- force traffic through the DUT or the explicit network path between the two arms

Typical use:

- firewall and L4 validation
- client/server and server/client symmetry tests
- full-duplex experiments
- stateful traffic at scale

Design rule:

- one role family per arm
- traversal must cross the physical or switched path
- no local shortcut that collapses both roles onto the same arm

### 1-arm mode

This is the client simulation mode against real servers.

Intent:

- generate client traffic from vMoonGen
- target real servers on the opposite side
- use high-level traffic objects called `superflows`

Typical use:

- real-server benchmarking
- progressive ramp against a live service cluster
- reproduction of a service mix without having to simulate both ends

## Superflows

`superflows` are the intended high-level traffic abstraction.

A superflow should describe:

- transport family: TCP now, pseudo-UDP now, SCTP later
- role: client or server
- L3/L4 identity
- connection behavior
- request or transaction profile
- payload sizing and pacing hints
- timers, retries, and teardown behavior

The long-term goal is that users manipulate superflows and scenarios, not low-level packet scripts.

## Scenario Phases

Every benchmark or campaign scenario should be representable with four canonical phases.

### 1. Target

Define the intended outcome:

- target rate
- target connection-per-second value
- target concurrency
- target service mix
- success criteria

### 2. Ramp

Increase load progressively until the target or candidate operating point is reached.

Examples:

- bandwidth ramp
- CPS ramp
- concurrency ramp

### 3. Steady

Hold the candidate point long enough to validate:

- drop behavior
- latency
- retries
- DUT stability
- session-state stability

### 4. Finish

Drain, stop creating new work, and let the active session population converge down cleanly.

This phase matters because:

- stateful DUTs can be distorted by abrupt stop conditions
- session cleanup behavior is part of the result
- realistic firewalls and L4 devices need an orderly tail

## Adaptive Timing

Scenario durations should not stay fully static.

The intended model is approximate auto-adjustment of phase durations based on:

- declared DUT class
- first-pass observed performance
- previous benchmark results
- whether the current run is exploratory or confirmatory

Examples:

- a weak DUT gets shorter ramp and shorter steady windows for the first discovery pass
- a stronger DUT gets longer steady windows once the candidate point is near the optimum
- finish windows scale with observed session population and teardown rate

This should remain heuristic and operator-visible, not opaque magic.

## Generic Firewall L4 Benchmark Plan

The baseline generic firewall L4 plan should include at least these three tests.

### Max bandwidth UDP IPv4

Goal:

- find the highest sustainable UDP IPv4 throughput that still meets the acceptance criteria

### Max connections per second TCP IPv4

Goal:

- find the highest sustainable TCP IPv4 CPS value that still meets the acceptance criteria

### Max concurrent sessions based on 50% of max CPS

Goal:

- use `50%` of the measured max TCP CPS as the session build rate
- find the highest stable concurrent session count

This is a good default because it separates:

- session creation capacity
- session holding capacity

## Acceptance Criteria

The exact pass/fail thresholds should remain configurable, but the generic default decision model is:

- `0` drop rate for benchmark validation unless the test explicitly allows otherwise
- acceptable mean latency or percentile threshold
- TCP setup allowed to use up to `3` retries
- no uncontrolled DUT instability

Possible latency criteria:

- mean latency under threshold
- `p95` under threshold
- `p99` under threshold

The criteria must be attached to the scenario, not inferred implicitly.

## Search Method

The preferred generic search method is dichotomy around the operating point.

Typical pattern:

1. probe a candidate load
2. observe pass/fail against the scenario criteria
3. narrow the interval
4. repeat until the acceptable operating point is bracketed closely enough

This should be used for:

- UDP bandwidth search
- TCP CPS search
- concurrent session search

Why this is preferred:

- it converges faster than naive linear sweeps
- it is easier to automate
- it reduces lab time during short PoCs

## Future Import Path

A future feature should import external traffic descriptions from Ixia BreakingPoint artifacts.

The intended path is:

- topology conversion
- profile conversion into superflows
- scenario conversion into the four canonical phases

That import layer should map external objects into vMoonGen-native objects rather than trying to preserve every vendor-specific detail one-to-one.

Target outputs of the converter:

- topology description
- superflow profiles
- scenario phases
- DUT target metadata
- acceptance criteria

## Minimal Controller Logic

The future controller should be able to:

- load a scenario
- discover or reuse baseline DUT capacity
- adapt phase durations approximately
- run the benchmark
- search for the optimum operating point
- produce structured results

## Results Model

Each run should emit enough data to drive the next run.

Minimum result set:

- achieved throughput
- achieved CPS
- achieved concurrency
- drops
- latency summary
- retry summary
- phase durations actually used
- verdict and stopping reason

That result set becomes the input for the next adaptive run.

## Scenario Wizard Target

The next practical UX step is a wizard that writes native scenario definitions.

Wizard v1 inputs:

- mode: `1-arm` or `2-arm`
- role mapping per arm
- base transport profile: `tcp-lite` or `pseudo-udp`
- target objective and acceptance thresholds
- phase durations and ramp style

Wizard output:

- a valid scenario object ready for compile and run
- deterministic defaults for fields not explicitly set

Reference schema:

## Priority Matrix (Client/Server)

### P0 / mandatory

- strict cross-arm behavior for `2-arm` mode
- explicit arm roles in scenario (`left_role`, `right_role`)
- explicit `1-arm` client to real-server semantics
- worker plan emits role and arm for each worker
- deterministic `run/replay/campaign` remains green on local + venus

### P1 / nice to have

- role-aware load split knobs and directional metrics
- wizard presets for `2-arm`, `1-arm`, and full-duplex modes
- first superflow profile packs for common client/server app mixes

### P2 / long term roadmap

- SCTP scenario model and execution path
- advanced topology import (multi-VLAN, VRF, external artifacts)
- adaptive controller tuning phase durations from previous runs

- [schemas/scenario/scenario-v1.schema.json](schemas/scenario/scenario-v1.schema.json)
- [examples/scenario/scenario-v1.example.json](examples/scenario/scenario-v1.example.json)
- [lua-dsl-v1.md](lua-dsl-v1.md)

## Topology Conversion Target

The converter path should be incremental and explicit.

Recommended order:

1. IPv4 no-VLAN baseline
2. VLAN tags
3. VRF mapping
4. SR-IOV placement hints
5. IPv6
6. SCTP profile descriptors

VPP should remain the owner of VLAN/VRF dataplane behavior. The converter maps source topology into vMoonGen-native objects and VPP configuration intents.

## Application Profile Database

The long-term model should include an application profile database to feed superflows.

Sources:

- curated built-in profile templates
- known benchmark profile packs
- optional offline profile extraction from pcap metadata

The profile database should stay detached from hot-path logic and remain usable without any AI dependency.
