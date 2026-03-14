# vMoonGen Architecture Overview

vMoonGen extends MoonGen with a **VPP backend**.

The goal is to allow MoonGen Lua scripts to control **VPP-managed TCP and UDP sessions** while keeping MoonGen’s existing packet-generation capabilities.

## Core Idea

MoonGen becomes a **control-plane orchestrator**.

VPP becomes the **data-plane engine**.
Lua Scripts
     │
     ▼
MoonGen Lua API
     │
     ▼
VPP Adapter Layer
     │
     ▼
VPP API Client
     │
     ▼
Running VPP Instance
     │
     ▼
DPDK NIC

