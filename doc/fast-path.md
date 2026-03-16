# Fast Path

The **fast-path (FP)** is responsible for high-speed packet generation
and measurement.

The lab uses:

    MoonGen + DPDK

MoonGen provides:

-   packet generation
-   latency measurement
-   throughput benchmarking

------------------------------------------------------------------------

# Architecture

    MoonGen script
          |
          v
    DPDK driver
          |
          v
    NIC hardware

Each MoonGen thread runs its own **LuaJIT VM**.

This allows:

-   multi-core packet generation
-   independent packet streams

------------------------------------------------------------------------

# Fast Path Tasks

Typical tasks:

-   generate traffic flows
-   measure latency distribution
-   measure throughput
-   stress dataplane components

Example scripts:

    examples/l2-load-latency.lua
    examples/l3-load-latency.lua
    examples/rate-control-methods.lua

------------------------------------------------------------------------

# Runtime

MoonGen typically runs in a **tmux session**.

Example:

    tmux new -s moongen
    sudo libmoon/MoonGen examples/l2-load-latency.lua 0 1

------------------------------------------------------------------------

# Metrics

Measurements include:

-   latency histogram
-   packet loss
-   throughput

Output files:

    histogram.csv
