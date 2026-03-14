# MoonGen VPP backend plan

## Goal
Add a VPP-capable backend to MoonGen so Lua scripts can control VPP-managed UDP/TCP traffic.

## Principles
- Keep existing MoonGen behavior unchanged
- Add VPP as an optional backend
- Start with control-plane integration, not dataplane replacement
- Let VPP manage transport/session logic

## Phase 1
- create VPP adapter structure
- define Lua API
- prove MoonGen can talk to a running VPP instance

## Phase 2
- add minimal connect/send/close operations
- add simple UDP test
- add simple TCP session test

## Phase 3
- performance and scaling work
- worker/session ownership design
