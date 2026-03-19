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

Optional but recommended on hybrid CPUs (P/E):

```bash
scripts/vmoongenctl plan-core-affinity --reserve-p-cores 4 --reserve-e-clients 6
source "$VPP_RUN_DIR/affinity.env"
```

This pins:

- VPP hot path on reserved P cores
- client-side workload on E cores
- remaining CPUs for system background tasks

For isolation-sensitive campaigns, enforce Linux headroom on E cores:

```bash
scripts/vmoongenctl plan-core-affinity \
  --reserve-p-cores 4 \
  --reserve-e-clients all \
  --system-min-cpus 2 \
  --system-min-e-cores 2
source "$VPP_RUN_DIR/affinity.env"
```

Increase `--system-min-e-cores` to `3` or `4` if the host is noisy.

Then continue with:

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

## Rebuilding VPP With `dpdk-stable`

The preferred rebuild path is now containerized and uses a separate `dpdk-stable` source tree.

Standard flow:

```bash
scripts/vmoongenctl check-vpp-build-sources
scripts/vmoongenctl build-vpp-image
scripts/vmoongenctl build-vpp-system-dpdk
scripts/vmoongenctl check-vpp-build
scripts/vmoongenctl check-vpp-fastpath
```

Key properties:

- build dependencies such as `nasm` live in the build container, not in the host user environment
- the DPDK install prefix is placed under the VPP tree in `build-root/install-system-dpdk`
- VPP is rebuilt with `VPP_USE_SYSTEM_DPDK=ON`

For the exact recipe, see [build-vpp-system-dpdk.md](build-vpp-system-dpdk.md).

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

## Efficiency KPIs

After a smoke run, compute P0/P1 efficiency values from artifacts:

```bash
scripts/vmoongenctl scenario-efficiency /tmp/vmoongen-scenario-smoke-venus/local/<stamp> --p-cores 4 --e-cores 6 --write-report
```

The report includes:

- P0: max CPS, CPS per P/E core, hot sessions per P core
- P1: PPS, per-worker PPS, estimated bandwidth at payload 1K and 10K
- cache hit rates when a `perf stat` file is provided
- CPU/cache profile auto-detection (when available) and L2 cache-fit pressure guidance for session scale tuning

For L7 stateful campaigns, model mixed lifetimes directly in DSL applications (for example `HTTP ttl=1800s` and `DNS ttl=5s`) to make concurrent-session estimates realistic.

Targeted campaign helper (cache-focused):

```bash
scripts/vmoongenctl scenario-campaign-cache examples/scenario-dsl/livebox_2arm_efficiency_f1.lua --workers 4 --iterations 4 --run-window 15m --p-cores 2 --e-cores 2
```

If `perf` is available, this command captures hardware counters and computes L1/L2/L3 hit/miss percentages automatically.

Recommended run-window policy:

- general campaigns: `5m`, `15m`, or `30m`
- CPS / max-sessions campaigns: `30m` to `60m`

Multi-KPI performance suite (20 terminals baseline + x2 ladder + optional x10 overload):

```bash
scripts/vmoongenctl scenario-perf-suite \
  --base-terminals 20 \
  --factors 1,2,4,8 \
  --extreme-factor 10 \
  --mbps-per-client 1 \
  --cps-per-client 500000 \
  --cpe-base 4 \
  --cpe-scale-with-factor \
  --udp-ttl-s 900 \
  --pcap-iface enp2s0f0np0 \
  --pcap-bytes 102400 \
  --iterations 4 \
  --workers 4 \
  --run-window-general 15m \
  --run-window-cps 30m \
  --out-dir /tmp/vmoongen-perf-suite \
  --baseline-report /tmp/vmoongen-perf-suite-prev/report_campaign.json
```

This suite runs independent KPI campaigns:

- `max_cps_tcp`
- `max_sessions_50pct_cps` (seeded from 50% of best CPS per factor)
- `max_bandwidth_tcp`
- `max_bandwidth_udp`

For `max_bandwidth_udp`, the suite now defaults to:

- simple `udp-echo-lite` application profile
- `session_ttl_s = 900`
- `2-arm` full-duplex (`client` and `server` active across the DUT path)

Per campaign, a capped pcap capture is produced (default 100 KiB):

- `<campaign>/campaign-capture.pcap`
- `<campaign>/campaign-capture-raw.pcap` (raw source, when capture succeeds)
- `<campaign>/pcap-trim.log`

Capture backend selection is automatic:

- `tcpdump` if present
- fallback `python AF_PACKET` capture helper when `tcpdump` is not installed

If the 10G NIC is fully owned by DPDK/VFIO, host-kernel capture can be empty (`24 bytes / 0 packet`).
In that case, keep this capture for campaign metadata and switch to VPP-side packet capture for dataplane payload analysis.

It generates a human-readable summary:

- `<suite-artifact>/report_campaign.txt`
- `<suite-artifact>/report_campaign.json`

and detects regressions:

- within current campaign factors (`x1 -> x2 -> x4 ...`)
- against a previous baseline report (if provided)

Roadmap/perf progression snapshot from a campaign report:

```bash
scripts/vmoongenctl scenario-progress /tmp/vmoongen-perf-suite/report_campaign.json --out-file /tmp/vmoongen-perf-suite/progress.md
```

`scenario-campaign-cache` and `scenario-perf-suite` now verify core isolation before starting:

- `VPP cpuset`, `client cpuset`, and `system cpuset` must be present and disjoint
- system cpuset must keep at least `VMOONGEN_SYSTEM_MIN_CPUS` CPUs
- system E-core cpuset must keep at least `VMOONGEN_SYSTEM_MIN_E_CORES` E cores
- on Linux, if cpusets are missing and auto-plan is enabled, the scripts generate and load an affinity plan automatically

Smoke and campaign runs now generate human-readable summaries:

- `<artifact>/smoke-summary-<utc-stamp>.txt`
- `<artifact>/campaign/campaign-summary.txt`
- `<artifact>/campaign/campaign-<campaign-id>-<utc-stamp>.txt`

## DAC Role Model

For the DAC lab:

- one role is attached to one X710 port
- the opposite role is attached to the other X710 port
- traffic must cross the DAC

Do not validate client/server on the same physical port.
