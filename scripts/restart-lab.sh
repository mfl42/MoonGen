#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/stop-fastpath.sh" || true
"$DIR/stop-daemon.sh" || true
sleep 1
"$DIR/start-daemon.sh"
sleep 1
"$DIR/start-fastpath.sh"
