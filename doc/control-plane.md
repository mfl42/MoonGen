# Control Plane

The **control-plane (CP)** manages configuration and orchestration of
the dataplane.

It interacts with **VPP** through a lightweight bridge daemon.

Architecture:

    Lua scripts
         |
         v
    vpp_bridge_daemon
         |
         v
    VPP CLI socket
         |
         v
    VPP dataplane

------------------------------------------------------------------------

# Responsibilities

The control plane:

-   configure VPP interfaces
-   query dataplane state
-   run diagnostics
-   orchestrate experiments

------------------------------------------------------------------------

# Current Model

Lua sends commands to the daemon:

    Lua -> daemon -> vppctl -> CLI socket

Output is parsed and returned as JSON.

Example response:

    {
     "ok": true,
     "output": "show version"
    }

------------------------------------------------------------------------

# Future Optimization

Planned architecture:

    Lua
     |
     v
    daemon
     |
     v
    VPP binary API

Benefits:

-   faster control operations
-   structured data
-   no text parsing
