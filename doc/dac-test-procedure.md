# DAC Test Procedure

*Last updated: 2026-03-16*

This procedure validates the **direct SFP+ DAC connection between two
NIC ports** on the same host.

Hardware example:

-   Intel X710 NIC
-   two SFP+ ports
-   passive DAC cable (10Gb)

Ports example:

    enp2s0f0np0
    enp2s0f1np1

------------------------------------------------------------------------

# 1 Verify NIC detection

    lspci | grep Ethernet

------------------------------------------------------------------------

# 2 Verify DPDK binding

    dpdk-devbind.py --status

Expected:

    drv=vfio-pci

------------------------------------------------------------------------

# 3 Connect DAC cable

Plug DAC between:

    port0 <-> port1

Check link:

    ip link

------------------------------------------------------------------------

# 4 Run MoonGen device check

    sudo libmoon/MoonGen examples/device-statistics.lua

------------------------------------------------------------------------

# 5 Run latency test

    sudo libmoon/MoonGen examples/l2-load-latency.lua 0 1

------------------------------------------------------------------------

# Expected Result

Packets should circulate through the DAC loop:

    TX port0 -> DAC -> RX port1
    TX port1 -> DAC -> RX port0

Latency histogram file:

    histogram.csv
