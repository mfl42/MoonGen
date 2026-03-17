# Operations

This document describes the current operating model for the vMoonGen lab.

## Standard Operating Sequence

### 1. Prepare the host

```bash
scripts/setup-host.sh
```

This step is responsible for:

- hugepages
- VFIO / NIC binding
- validating fast-path prerequisites

### 2. Start VPP on the host

```bash
scripts/vmoongenctl check-vpp-fastpath
scripts/vmoongenctl check-vpp-build
scripts/render-vpp-session-conf.sh
scripts/start-vpp-host.sh
```

Check it with:

```bash
scripts/status-vpp-host.sh
```

### 3. Start the toolbox control-plane

```bash
scripts/vmoongenctl start-lab
```

In the current default mode, `start-lab` assumes host preparation and host-side VPP are already handled.

### 4. Check fast-path readiness

```bash
scripts/vmoongenctl check-fp-ready
```

This check now includes VPP dataplane mode detection. On `venus` today, it fails intentionally if the installed VPP build cannot own the X710 PF DAC pair.

### 5. Start MoonGen-side workload if needed

```bash
scripts/vmoongenctl start-fp
```

This step is optional for VPP/DPDK fast-path bring-up itself. It is for MoonGen-side validation or orchestration workloads.

### 6. Observe the system

```bash
scripts/vmoongenctl status-cp
scripts/vmoongenctl status-fp
scripts/status-vpp-host.sh
```

## Stop and Restart

Stop the fast path:

```bash
scripts/vmoongenctl stop-fp
```

Restart the fast path:

```bash
scripts/vmoongenctl restart-fp
```

Stop the toolbox control-plane:

```bash
scripts/vmoongenctl stop-lab
```

Stop VPP on the host:

```bash
scripts/stop-vpp-host.sh
```

## Typical Paths

Current real paths on `venus`:

```text
/home/mfl42/Projects/vMoonGen
/home/mfl42/Projects/vpp
```

Those are current deployment paths, not hard requirements.

The project can also be relocated by setting environment variables such as:

- `VMOONGEN_ROOT`
- `VPP_ROOT`
- `VMOONGEN_VPP_ROOT`
- `VPP_SOCKET`

## Logs

Important logs:

- `logs/lab-actions.log`
- `logs/fast-path-actions.log`
- `logs/fast-path-runtime.log`
- `logs/vpp.log`

The control-plane daemon itself is launched directly and is also visible through:

```bash
scripts/vmoongenctl status-cp
```

## Operating Modes

### Toolbox-only default

This is the current default mode for `start-lab`.

Assumption:

- host prep is done separately
- VPP is already running on the host
- toolbox scripts only manage the daemon and MoonGen side

### Combined mode

The scripts can still be driven from one machine for development, but host and toolbox responsibilities remain logically separate.

## Runtime Automation Notes

Current canonical runtime choices in this repository:

- VPP host process: shell-managed, log-backed, containerized
- control-plane daemon: shell-managed with socket and pid tracking
- MoonGen-side workload: `nohup` plus pid/log files
- operator interface: `scripts/vmoongenctl`

## Current `venus` dataplane blocker

On `venus` as of March 17, 2026:

- the installed VPP `v26.06-rc0` build does not ship `dpdk_plugin.so`
- the visible new-framework drivers are `ige`, `iavf`, and `idpf`
- those drivers do not support the X710 PF pair used for the DAC lab

Result:

- control-plane VPP bring-up works
- X710 DAC dataplane bring-up in VPP is still blocked until VPP is rebuilt or reinstalled with classic DPDK / `i40e` support
- current rebuild attempts on `venus` are additionally blocked by missing `nasm`, required while building `ipsec-mb` in the external dependency chain

## Resource Containment

Observed on `venus` on March 17, 2026:

- `vpp_main` uses about `350 MiB` RSS and keeps one polling core busy
- the VPP container wrapper adds about `57 MiB` RSS
- the Python control-plane daemon stays near `15 MiB` RSS

Practical footprint controls:

- use `VMOONGEN_VPP_FASTPATH_MODE=cp-only` when only the control plane is needed
- keep `VMOONGEN_VPP_WORKERS=1` for lighter tests
- keep `VMOONGEN_VPP_RX_QUEUES=1` and `VMOONGEN_VPP_TX_QUEUES=1` unless a test needs more queue parallelism
- keep `VMOONGEN_VPP_RX_QUEUE_SIZE=512` and `VMOONGEN_VPP_TX_QUEUE_SIZE=512` unless deeper buffering is required
- keep MoonGen stopped unless the scenario explicitly needs a front-end workload
- keep rebuilds capped with `MAKE_PARALLEL_JOBS=4` or lower on `venus`

Earlier notes about `tmux` or `systemd --user` are still valid as optional deployment styles, but they are not the default operating model currently implemented here.

## DAC Role Model

For the DAC lab:

- one role is attached to one X710 port
- the opposite role is attached to the other X710 port
- traffic must cross the DAC

Do not validate client/server on the same physical port.
