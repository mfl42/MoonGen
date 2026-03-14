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
