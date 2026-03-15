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
q!

