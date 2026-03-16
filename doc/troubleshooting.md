# Troubleshooting

*Last updated: 2026-03-16*

## VPP not responding

Check VPP status:

    vppctl -s ~/Projects/vpp/run/cli.sock show version

If the socket is missing:

    ls ~/Projects/vpp/run

Restart VPP:

    scripts/restart-fastpath.sh

------------------------------------------------------------------------

## DPDK devices not detected

Check device binding:

    dpdk-devbind.py --status

Expected:

    drv=vfio-pci

If not:

    scripts/dpdk-bind.sh

------------------------------------------------------------------------

## Hugepages problems

Check hugepages:

    grep Huge /proc/meminfo

Setup again:

    scripts/setup-host.sh

------------------------------------------------------------------------

## MoonGen cannot start

Check NICs:

    scripts/check-nics.sh

Check lab environment:

    scripts/check-lab.sh

------------------------------------------------------------------------

## VPP daemon connection refused

Check daemon logs:

    journalctl --user -u vpp_bridge_daemon
