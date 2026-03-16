#!/usr/bin/env bash

ROOT="$HOME/Projects/vMoonGen"

echo
echo "===================================="
echo " MoonGen Device Statistics"
echo "===================================="
echo

sudo "$ROOT/libmoon/MoonGen" "$ROOT/examples/device-statistics.lua"
