# Backend interface

Backends must expose these methods:

- connect(payload)
- disconnect(payload)
- install_profile(payload)
- start_profile(payload)
- stop_profile(payload)
- remove_profile(payload)
- get_profile_stats(payload)
- list_profiles(payload)

Rules:
- return Python dicts on success
- raise ValueError for user/input errors
- raise other exceptions for backend/runtime errors
# Backend interface

Backends must expose these methods:

- connect(payload)
- disconnect(payload)
- install_profile(payload)
- start_profile(payload)
- stop_profile(payload)
- remove_profile(payload)
- get_profile_stats(payload)
- list_profiles(payload)

## Rules

- return Python dicts on success
- raise `ValueError` for user or input errors
- raise other exceptions for backend or runtime errors

## Current backends

- `MockBackend` in `tools/vpp_backend_mock.py`
- `VPPBackend` in `tools/vpp_backend_vpp.py`

## Selection

The bridge selects the backend with the `VMOONGEN_BACKEND` environment variable.

Supported values:
- `mock`
- `vpp`

Default:
- `mock`
