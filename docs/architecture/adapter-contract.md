# Adapter contract

The vMoonGen adapter contract is a JSON request/response protocol between Lua control logic and the backend bridge.

## Goals

- stable interface across mock and real backends
- profile-oriented control
- backend isolation
- simple observability and error reporting

## Request schema

```json
{
  "version": 1,
  "action": "connect | disconnect | install_profile | start_profile | stop_profile | remove_profile | get_profile_stats | list_profiles",
  "payload": {}
}
```md
# Adapter Contract

The adapter contract defines communication between:

Lua control logic and backend adapter.

The contract uses **JSON request/response messages**.

This isolates MoonGen from backend implementation.

## Request format
{
“version”: 1,
“action”: “action_name”,
“payload”: {}
}
{
“version”: 1,
“action”: “action_name”,
“payload”: {}
}
## Response format
{
“ok”: true,
“version”: 1,
“data”: {}
}

Error response:
{
“ok”: false,
“version”: 1,
“error”: “error message”
}

## Supported actions

| Action | Description |
|------|-------------|
| connect | connect to backend |
| disconnect | close backend connection |
| install_profile | register workload |
| start_profile | start workload |
| stop_profile | stop workload |
| remove_profile | remove workload |
| get_profile_stats | retrieve metrics |
| list_profiles | list installed profiles |

## Example request
{
“version”:1,
“action”:“connect”,
“payload”:{
“socket_path”:”/run/vpp/api.sock”
}
}

## Example response
{
“ok”:true,
“version”:1,
“data”:{
“connected”:true
}
}
## Design rules

- Lua defines profiles
- Adapter remains thin
- VPP owns session logic
- Control operations are batch oriented

## Implementation layering

The adapter is split into two layers:

1. `vpp_contract_bridge.py`
   - parses JSON requests
   - validates protocol version
   - dispatches actions
   - formats JSON responses

2. `vpp_backend_mock.py`
   - implements backend behavior
   - stores mock state
   - simulates profile lifecycle and stats

This separation allows a future real backend such as `vpp_backend_vpp.py` to be added without changing the Lua API or the contract format.
## Implementation layering

The adapter is split into two layers:

1. `vpp_contract_bridge.py`
   - parses JSON requests
   - validates protocol version
   - dispatches actions
   - formats JSON responses

2. `vpp_backend_mock.py`
   - implements backend behavior
   - stores mock state
   - simulates profile lifecycle and stats

This separation allows a future real backend such as `vpp_backend_vpp.py` to be added without changing the Lua API or the contract format.
## Implementation layering

The adapter is split into two layers:

1. `vpp_contract_bridge.py`
   - parses JSON requests
   - validates protocol version
   - dispatches actions
   - formats JSON responses

2. `vpp_backend_mock.py`
   - implements backend behavior
   - stores mock state
   - simulates profile lifecycle and stats

This separation allows a future real backend such as `vpp_backend_vpp.py` to be added without changing the Lua API or the contract format.
## Backend selection

The bridge selects its backend with the `VMOONGEN_BACKEND` environment variable.

Supported values:
- `mock`
- `vpp`

Example:

```bash
VMOONGEN_BACKEND=mock python3 tools/vpp_contract_bridge.py
## Backend selection

The bridge selects its backend with the `VMOONGEN_BACKEND` environment variable.

Supported values:
- `mock`
- `vpp`

Example:

```bash
printf '%s' '{"version":1,"action":"list_profiles","payload":{}}' | VMOONGEN_BACKEND=mock python3 tools/vpp_contract_bridge.py
## Backend selection

The bridge selects its backend with the `VMOONGEN_BACKEND` environment variable.

Supported values:
- `mock`
- `vpp`

Example:

```bash
printf '%s' '{"version":1,"action":"list_profiles","payload":{}}' | VMOONGEN_BACKEND=mock python3 tools/vpp_contract_bridge.py
