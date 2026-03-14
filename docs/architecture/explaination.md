Components

Lua Scripts

User-written traffic scenarios.

Example:
local vpp = require "vpp"

vpp.connect()

vpp.udp_send({...})
vpp.tcp_connect({...})

Lua API (lua/vpp.lua)

Defines the user-facing API.

Responsibilities:
	•	expose session operations
	•	call the adapter bridge
	•	return results to Lua scripts

Adapter Layer (src/vpp_adapter)

Responsible for communication with VPP.

Responsibilities:
	•	translate Lua operations into VPP API calls
	•	manage sessions
	•	manage connection lifecycle

VPP API Client

Handles communication with the running VPP instance.

VPP exposes a binary API over a Unix socket (typically /run/vpp/api.sock).  ￼

Messages are exchanged using request/reply semantics.

VPP Instance

Handles:
	•	packet processing
	•	TCP stack
	•	UDP flows
	•	routing
	•	NIC interaction

Design Goals
	•	minimal changes to MoonGen
	•	backend abstraction
	•	support millions of sessions
	•	keep Lua scripting model

---

# 3️⃣ `docs/architecture/vpp-backend.md`

Put this:

```md
# VPP Backend Design

This document describes the VPP backend for vMoonGen.

## Backend Types

MoonGen currently supports:

- raw packet generation (DPDK)

vMoonGen adds:

- VPP-managed session backend

MoonGen
├── DPDK packet engine
└── VPP session backend

## Communication with VPP

Communication uses the **VPP Binary API**.

This API is a message-based RPC interface between control-plane clients and the VPP dataplane.  [oai_citation:1‡s3-docs.fd.io](https://s3-docs.fd.io/vpp/23.10/interfacing/binapi/vpp_api_language.html?utm_source=chatgpt.com)

Messages are exchanged via:

Clients send requests and receive replies.

## VPP API Client

The project will initially use a **Python client wrapper**.

The official Python interface is provided by `vpp_papi`.

It dynamically loads API definitions and creates callable functions.  [oai_citation:2‡DeepWiki](https://deepwiki.com/FDio/vpp/1.6.2-vpp-api-system?utm_source=chatgpt.com)

Example:

```python
from vpp_papi import VPPApiClient

vpp = VPPApiClient()
vpp.connect("client")

version = vpp.api.show_version()

Lua Integration

Lua calls the bridge:

lua script
   ↓
lua/vpp.lua
   ↓
bridge (python)
   ↓
VPP API

Future Direct Integration

Later versions may replace the Python bridge with:
	•	native C API client
	•	LuaJIT FFI bindings

Session Model

Each session stores:
	•	source IP
	•	destination IP
	•	ports
	•	protocol
	•	VPP session ID

Example:

Session {
  id
  protocol (TCP/UDP)
  src_ip
  dst_ip
  src_port
  dst_port
}

Session {
  id
  protocol (TCP/UDP)
  src_ip
  dst_ip
  src_port
  dst_port
}

Scaling Model

VPP scales using worker threads.

Each worker handles a shard of sessions.
core0 → session shard 0

core1 → session shard 1
core2 → session shard 2

This enables millions of concurrent flows.

Roadmap

Phase 1

mock bridge

Phase 2

real VPP API integration

Phase 3

session scaling

Phase 4

native Lua binding

---
