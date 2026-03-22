# Fast Path

The intended fast path is VPP + DPDK using the X710 port pair as a real cross-port dataplane.

## Current Role

Today the fast path is responsible for:

- owning the DPDK ports
- running the VPP transport and session stack
- carrying client/server traffic across the DAC
- keeping client and server roles split across physical ports

## Current Prerequisites

Before the VPP fast path can start, the host must provide:

- hugepages
- X710 ports bound to `vfio-pci`
- DPDK-ready host state
- a VPP session config that enables DPDK on both ports

The repository now checks those prerequisites explicitly through:

- [scripts/check-fastpath-ready.sh](../scripts/check-fastpath-ready.sh)
- [scripts/check-vpp-fastpath-support.sh](../scripts/check-vpp-fastpath-support.sh)
- [scripts/render-vpp-session-conf.sh](../scripts/render-vpp-session-conf.sh)

## Current Startup Path

Typical flow:

```text
scripts/setup-host.sh
  -> scripts/render-vpp-session-conf.sh
  -> scripts/start-vpp-host.sh
  -> scripts/vmoongenctl start-lab
```

The current repository still contains a MoonGen-side workload entrypoint:

- [examples/vpp_multithread_control.lua](../examples/vpp_multithread_control.lua)

That script is useful for:

- front-end validation
- control-plane exercise
- integration bring-up

It should not be treated as the target transport fast path itself.

## Current `venus` Blocker

On `venus` today, the installed VPP build does not include `dpdk_plugin.so`.

What it does expose:

- `ige_driver.so`
- `iavf_driver.so`
- `idpf_plugin.so`

Why that matters:

- the DAC pair is an Intel X710 PF pair (`8086:1572`)
- `ige` only covers I211 / I225 / I226 class devices
- `iavf` covers Intel VFs, not the X710 PF
- `idpf` targets newer Intel devices

So the current X710 DAC dataplane is blocked in VPP until the host installs a VPP build with classic DPDK / `net_i40e` support.

## DAC Cross-Port Rule

The DAC topology must be used as a true crossing path:

```text
client on port 0 -> DAC -> server on port 1
client on port 1 -> DAC -> server on port 0
```

Forbidden topology for transport validation:

```text
client and server on the same physical port
```

## Runtime Notes

The VPP fast path is driven by the host-side VPP lifecycle:

- [scripts/render-vpp-session-conf.sh](../scripts/render-vpp-session-conf.sh)
- [scripts/start-vpp-host.sh](../scripts/start-vpp-host.sh)
- [scripts/status-vpp-host.sh](../scripts/status-vpp-host.sh)
- [scripts/stop-vpp-host.sh](../scripts/stop-vpp-host.sh)

The repository also keeps MoonGen-side helpers:

- [scripts/start-fastpath.sh](../scripts/start-fastpath.sh)
- [scripts/status-fastpath.sh](../scripts/status-fastpath.sh)
- [scripts/stop-fastpath.sh](../scripts/stop-fastpath.sh)
- [scripts/restart-fastpath.sh](../scripts/restart-fastpath.sh)

Runtime logs are stored under `logs/`.

Each new MoonGen-side workload launch archives the previous runtime log to a `.bak` file before starting a fresh run.

## Design Rule

The control plane may observe or steer the experiment, but it must not sit in the packet hot path.

That rule is central to the scalability target of the project.
