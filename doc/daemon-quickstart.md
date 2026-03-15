# vMoonGen Persistent Bridge Quick Start

## 1. Start the bridge daemon

Run from the repository root:

    VMOONGEN_BACKEND=vpp python3 tools/vpp_bridge_daemon.py --socket /tmp/vmoongen.sock

## 2. Verify the daemon with Lua

    lua examples/vpp_daemon_test.lua

## 3. Run the multithreaded example with MoonGen

    sudo ./build/MoonGen examples/vpp_multithread_control.lua <txDev>

The example uses:

- one control task
- multiple TX worker tasks
- a persistent daemon for the VPP control plane

## Notes

- `lua/vpp_socket.lua` uses LuaJIT FFI and is intended for MoonGen runtime.
- the VPP CLI socket path currently defaults to:

    /home/mfl42/Projects/vpp/run/cli.sock

Adjust it in the example scripts if needed.
