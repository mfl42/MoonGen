Example content:

```markdown
# MoonGen – VPP Integration Architecture

This document describes the experimental MoonGen integration with VPP.

## Goals

Provide a lightweight control path allowing MoonGen Lua scripts to
control and inspect a running VPP instance.

## Design Principles

- No modification of the VPP core
- Minimal Lua dependencies
- JSON contract between Lua and Python
- Simple CLI-based backend

## Components

### Lua Module

File:
lua/vpp.lua

Responsibilities:

- Encode requests to JSON
- Call the Python bridge
- Return raw responses

### Python Bridge

File:

tools/vpp_contract_bridge.py

Responsibilities:

- Receive JSON requests
- Dispatch to backend
- Return JSON response

### VPP Backend

File:
tools/vpp_backend_vpp.py
Responsibilities:

- Execute `vppctl`
- Connect to CLI socket
- Translate responses

## Communication Contract

Request format:

```json
{
  "version": 1,
  "action": "show_version",
  "payload": {
    "socket_path": "/path/to/cli.sock"
  }
}
Response format:
{
  "ok": true,
  "version": 1,
  "data": {
    "output": "..."
  }
}

Current Limitations
	•	CLI-based interaction
	•	No binary VPP API yet
	•	Output parsing not implemented

Future work may include:
	•	VPP binary API integration
	•	session orchestration
	•	MoonGen packet pipeline coupling

---

# 3️⃣ Add a quick start example

Create:
docs/examples/vpp-control.md
Example:

```markdown
# VPP Control Example

Start VPP:
vpp -c run/vpp-session.conf
Run the Lua test:
lua examples/vpp_live_test.lua
Example output:
vpp v26.06
interfaces:
local0 up

