#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

if [[ -x "$ROOT/scripts/dpdk-bind.sh" ]]; then
	exec "$ROOT/scripts/dpdk-bind.sh" "$@"
fi

if [[ -x "$ROOT/libmoon/bind-interfaces.sh" ]]; then
	(
		cd "$ROOT/libmoon"
		ERROR_MSG_SUBDIR="libmoon/" ./bind-interfaces.sh "$@"
	)
	exit 0
fi

echo "libmoon helper not found at $ROOT/libmoon/bind-interfaces.sh" >&2
echo "Please run git submodule update --init --recursive" >&2
exit 1
