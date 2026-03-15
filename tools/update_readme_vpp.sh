#!/usr/bin/env bash

set -e

README="README.md"

TMP=$(mktemp)

cat > "$TMP" <<'EOF'

## VPP Integration (Experimental)

This branch introduces an **experimental integration between MoonGen and FD.io VPP** (Vector Packet Processing).

The integration allows **Lua scripts to control a running VPP instance** through a lightweight Python bridge.

The goal is to enable MoonGen scripts to **inspect, configure, and orchestrate VPP during traffic generation experiments.**

---

## Architecture

```mermaid
graph TD

MoonGen["MoonGen Lua Script"]
Lua["lua/vpp.lua"]
Bridge["tools/vpp_contract_bridge.py"]
Backend["tools/vpp_backend_vpp.py"]
VPP["VPP CLI socket"]

MoonGen --> Lua
Lua --> Bridge
Bridge --> Backend
Backend --> VPP
