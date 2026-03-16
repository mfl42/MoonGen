# vMoonGen Operations Guide

This document describes how to operate the local vMoonGen lab with separate **Fast-Path (FP)** and **Control-Plane (CP)** actions and logs.

---

## Concepts

### Control-Plane (CP)

The control-plane includes:

- VPP process
- bridge daemon
- CLI or LuaJIT control requests

### Fast-Path (FP)

The fast-path includes:

- MoonGen DPDK dataplane
- TX/RX worker threads
- dataplane test scripts

---

## Log Files

The scripts create the following log files under:

    $HOME/Projects/vMoonGen/logs

### Control-Plane logs

- `control-plane-actions.log`
  - human-readable action log
  - records start/stop/restart/status actions

- `control-plane-daemon.log`
  - daemon stdout/stderr
  - useful when the UNIX socket exists but requests fail

### Fast-Path logs

- `fast-path-actions.log`
  - human-readable lifecycle log for MoonGen

- `fast-path-runtime.log`
  - MoonGen stdout/stderr
  - useful for DPDK startup issues, link wait, and runtime exceptions

---

## Recommended Startup Order

### Control-plane

1. Start VPP in the container
2. Verify VPP:

       vppctl -s ~/Projects/vpp/run/cli.sock show version

3. Start daemon:

       ./scripts/start-daemon.sh

4. Verify daemon:

       ./scripts/status-controlplane.sh

### Fast-path

1. Confirm DPDK binding with:

       ./scripts/status-fastpath.sh

2. Start MoonGen dataplane:

       ./scripts/start-fastpath.sh

3. Inspect logs:

       tail -f ~/Projects/vMoonGen/logs/fast-path-runtime.log

---

## Recommended Shutdown Order

### Stop fast-path first

    ./scripts/stop-fastpath.sh

### Then stop daemon if needed

    ./scripts/stop-daemon.sh

VPP may remain running if you still need the control-plane.

---

## DAC Bring-Up Checklist

Once the DAC cable is connected between the two X710 ports:

1. ensure both X710 ports are still bound to `vfio-pci`
2. stop any stale MoonGen process
3. clear DPDK runtime locks
4. relaunch a single dataplane test

Suggested sequence:

    ./scripts/stop-fastpath.sh
    ./scripts/start-fastpath.sh

or directly:

    sudo ~/Projects/vMoonGen/libmoon/MoonGen examples/l2-load-latency.lua 0 1

---

## Common Recovery Procedures

### Stale MoonGen lock

Symptoms:

- `Cannot create lock on '/var/run/dpdk/rte/config'`
- `Found 0 usable devices` on relaunch

Recovery:

    ./scripts/stop-fastpath.sh

### Daemon socket missing

Symptoms:

- `connect: No such file or directory`

Recovery:

    ./scripts/start-daemon.sh

### VPP socket present but not listening

Symptoms:

- `connect: Connection refused`

Recovery:

1. restart VPP in the container
2. verify `vppctl ... show version`
3. restart daemon if needed

---

## Suggested Routine

### Status

    ./scripts/status-controlplane.sh
    ./scripts/status-fastpath.sh

### Restart only MoonGen

    ./scripts/restart-fastpath.sh

### Restart operator-managed services

    ./scripts/restart-lab.sh

---

## Notes

- Run MoonGen as root
- Keep management NIC untouched
- Only the two X710 SFP+ ports should stay under `vfio-pci`
- The DAC enables dataplane traffic, but the control-plane can be tested without it
