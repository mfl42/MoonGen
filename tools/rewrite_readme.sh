#!/usr/bin/env bash
set -e

cat > README.md <<'README_EOF'
### TL;DR
LuaJIT + DPDK = fast and flexible packet generator for 100 Gbit/s Ethernet and beyond.
MoonGen uses hardware features for accurate and precise latency measurements and rate control.

Skip to [Installation](#installation) and [Usage](#using-moongen) if you just want to send some packets.
The emulation of network paths is explained in [MoonEm](#moonem).

* Detailed evaluation: [Paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) (IMC 2015, [BibTeX entry](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015-BibTeX.txt))
* Detailed evaluation of path emulation capabilities: [Paper](https://dl.acm.org/doi/10.1145/3768976) (CoNEXT 2025, [BibTeX entry](https://net.in.tum.de/publications/bibtex/lachnit2025moonem.bib))

# MoonGen Packet Generator

MoonGen is a scriptable high-speed packet generator built on [libmoon](https://github.com/tumi8/libmoon).
The whole load generator is controlled by a Lua script: all packets that are sent are crafted by a user-provided script.
Thanks to the incredibly fast LuaJIT VM and the packet processing library DPDK, it can saturate a 10 Gbit/s Ethernet link with 64 Byte packets while using only a single CPU core.
MoonGen can achieve this rate even if each packet is modified by a Lua script. It does not rely on tricks like replaying the same buffer.

MoonGen can also receive packets, e.g., to check which packets are dropped by a
system under test. As the reception is also fully under control of the user's
Lua script, it can be used to implement advanced test scripts. E.g. one can use
two instances of MoonGen that establish a connection with each other. This
setup can be used to benchmark middle-boxes like firewalls.

MoonGen focuses on four main points:

* High performance and multi-core scaling: > 20 million packets per second per CPU core
* Flexibility: Each packet is crafted in real time by a user-provided Lua script
* Precise and accurate timestamping: Timestamping with sub-microsecond precision on commodity hardware
* Precise and accurate rate control: Reliable generation of arbitrary traffic patterns on commodity hardware

You can have a look at [our slides from a talk](https://raw.githubusercontent.com/tumi8/MoonGen/v22.11/doc/Slides.pdf) or read [our paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) [1] for a more detailed discussion of MoonGen's internals.


# Architecture
MoonGen is built on [libmoon](https://github.com/tumi8/libmoon), a Lua wrapper for DPDK.


Users can write custom scripts for their experiments. It is recommended to make use of hard-coded setup-specific constants in your scripts. The script is the configuration, it is beside the point to write a complicated configuration interface for a script.
Alternatively, there is a simplified (and less powerful) command-line interface available for quick tests.

The following diagram shows the architecture and how multi-core support is handled.

<p align="center">
<img alt="Architecture" src="https://raw.githubusercontent.com/tumi8/MoonGen/v22.11/doc/img/moongen-architecture.png" srcset="https://raw.githubusercontent.com/tumi8/MoonGen/v22.11/doc/img/moongen-architecture.png 1x, https://raw.githubusercontent.com/tumi8/MoonGen/v22.11/doc/img/moongen-architecture@2x.png 2x"/>
</p>

Execution begins in the *master task* that must be defined in the userscript.
This task configures queues and filters on the used NICs and then starts one or more *slave tasks*.

Note that Lua does not have any native support for multi-threading.
MoonGen therefore starts a new and completely independent LuaJIT VM for each thread.
The new VMs receive serialized arguments: the function to execute and arguments like the queue to send packets from.
Threads only share state through the underlying library.

The example script [quality-of-service-test.lua](https://github.com/tumi8/MoonGen/blob/v22.11/examples/quality-of-service-test.lua?ts=4) shows how this threading model can be used to implement a typical load generation task.
It implements a QoS test by sending two different types of packets and measures their throughput and latency. It does so by starting two packet generation tasks: one for the background traffic and one for the prioritized traffic.
A third task is used to categorize and count the incoming packets.


# Hardware Timestamping
Intel commodity NICs from the ice, igb, ixgbe, and i40e families support timestamping in hardware for both transmitted and received packets.
The NICs implement this to support the IEEE 1588 PTP protocol, but this feature can be used to timestamp almost arbitrary UDP packets.
MoonGen achieves a precision and accuracy of below 100 ns.

Use ``test-timestamping-capabilities.lua`` in ``examples/timestamping-tests`` to test your NIC's timestamping capabilities.

A more detailed evaluation can be found in [our paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) [1].

# Installation

1. Install the dependencies (see below)
2. ./build.sh --noBind
3. sudo ./bind-interfaces.sh
4. sudo ./setup-hugetlbfs.sh
5. sudo ./build/MoonGen examples/l3-load-latency.lua 0 1

Note: You need to bind NICs to DPDK to use them. `bind-interfaces.sh` does this for all unused NICs (no routing table entry in the system).
Use `libmoon/deps/dpdk/usertools/dpdk-devbind.py ` to manage NICs manually.


## Dependencies
* gcc >= 4.8
* make
* cmake
* meson
* ninja-build
* pkg-config
* python3-pyelftools
* libnuma-dev
* libsystemd-dev
* kernel headers (for the DPDK igb-uio driver)
* lspci (for `dpdk-devbind.py`)
* additional dependencies for Mellanox NICs

Run the following command to install these on Debian/Ubuntu:

```bash
sudo apt-get install -y build-essential cmake linux-headers-`uname -r` pciutils libnuma-dev meson ninja-build pkg-config python3-pyelftools libsystemd-dev

