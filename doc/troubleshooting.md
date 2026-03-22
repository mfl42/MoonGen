# Troubleshooting

*Last updated: 2026-03-17*

## VPP is not reachable

Symptoms:

- `status-cp` reports VPP unreachable
- `vppctl` fails on the configured socket

Checks:

```bash
scripts/status-vpp-host.sh
scripts/vmoongenctl status-cp
```

Common causes:

- VPP container not started
- stale `cli.sock`
- wrong `VPP_ROOT` or `VPP_SOCKET`

Recovery:

```bash
scripts/start-vpp-host.sh
```

## The control-plane daemon is missing

Symptoms:

- `/tmp/vmoongen.sock` absent
- `status-cp` shows no daemon process

Checks:

```bash
scripts/vmoongenctl status-cp
```

Recovery:

```bash
scripts/vmoongenctl start-lab
scripts/vmoongenctl start-daemon
```

## `check-fp-ready` fails

Symptoms:

- hugepages not configured
- NICs still on the kernel driver
- `vfio-pci` binding missing

Checks:

```bash
scripts/vmoongenctl check-fp-ready
scripts/check-nics.sh
```

Recovery:

```bash
scripts/setup-host.sh
```

## `render-vpp-session-conf.sh` refuses the DAC pair

Symptoms:

- `check-vpp-fastpath` fails
- `render-vpp-session-conf.sh` exits before writing a dataplane config
- the message mentions missing `dpdk_plugin.so` or unsupported X710 PF support

Checks:

```bash
scripts/vmoongenctl check-vpp-fastpath
scripts/status-vpp-host.sh
```

Common cause on `venus`:

- the installed VPP build exposes `ige` / `iavf` / `idpf`
- it does not ship `dpdk_plugin.so`
- the DAC ports are Intel X710 PFs (`8086:1572`), which still need classic DPDK / `i40e` support in this setup

Recovery:

```bash
export VMOONGEN_VPP_FASTPATH_MODE=cp-only
scripts/start-vpp-host.sh
```

That keeps the control plane available. For the real DAC dataplane, rebuild or reinstall VPP with classic DPDK support.

## VPP rebuild still does not produce `dpdk_plugin.so`

Symptoms:

- `scripts/vmoongenctl check-vpp-fastpath` still reports missing `dpdk_plugin.so`
- `scripts/vmoongenctl check-vpp-build` reports missing `libdpdk.a`, `libdpdk.pc`, or `nasm`

Checks:

```bash
scripts/vmoongenctl check-vpp-build
```

Common cause on `venus`:

- `build-dpdk` contains compiled DPDK objects
- but `install-vpp-native/external/lib/libdpdk.a` is still absent
- the external dependency chain rebuilds `ipsec-mb`
- `ipsec-mb` currently fails because `nasm` is not installed in the build environment

Recovery:

- keep `VMOONGEN_VPP_FASTPATH_MODE=cp-only` for control-plane availability
- install or provide `nasm` in the VPP build environment
- rerun the external install and the VPP rebuild only after `scripts/vmoongenctl check-vpp-build` goes green

## MoonGen exits immediately

Symptoms:

- `start-fp` fails
- no MoonGen process remains alive

Checks:

```bash
scripts/vmoongenctl check-fp-deps
scripts/vmoongenctl check-fp-ready
scripts/vmoongenctl status-fp
tail -n 80 logs/fast-path-runtime.log
```

Common causes:

- missing runtime libraries
- DPDK prerequisites not satisfied
- stale DPDK runtime files
- invalid test script or bad port arguments

Recovery:

```bash
scripts/vmoongenctl stop-fp
scripts/dpdk-reset.sh
scripts/setup-host.sh
scripts/vmoongenctl start-fp
```

## DPDK devices are not detected

Checks:

```bash
scripts/check-nics.sh
```

Expected for the X710 ports:

```text
drv=vfio-pci
```

If the ports still appear with `drv=i40e`, they are still owned by the kernel and MoonGen will not see them.

## Hugepages look wrong

Checks:

```bash
grep Huge /proc/meminfo
scripts/vmoongenctl check-fp-ready
```

Recovery:

```bash
scripts/setup-hugepages.sh
```

## Fast-path log is confusing

Each new `start-fp` now archives the previous runtime log to a timestamped `.bak` file.

If you are reviewing a failure, make sure you are looking at the latest `logs/fast-path-runtime.log` and not an older archived run.
