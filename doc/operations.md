# Lab Operations

## Start the Lab

    scripts/start-lab.sh

This will:

-   start VPP
-   start control-plane daemon
-   prepare DPDK environment

------------------------------------------------------------------------

## Stop the Lab

    scripts/stop-lab.sh

------------------------------------------------------------------------

## Restart Fast Path

    scripts/restart-fastpath.sh

------------------------------------------------------------------------

## Check Status

Control plane:

    vmoongenctl status-cp

Fast path:

    vmoongenctl status-fp

------------------------------------------------------------------------

## Logs

Scripts logs:

    logs/

Daemon logs:

    journalctl --user -u vpp_bridge_daemon
