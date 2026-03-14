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
