#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vmoongen-env.sh
source "$SCRIPT_DIR/vmoongen-env.sh"

HUGEPAGES_SYSFS="/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
TARGET_PAGES="${1:-$VMOONGEN_HUGEPAGES}"
MOUNT_POINT="${VMOONGEN_HUGEPAGES_MOUNT:-/dev/hugepages}"

run_root() {
	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

write_root_file() {
	local value="$1"
	local path="$2"
	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		printf '%s\n' "$value" >"$path"
	else
		printf '%s\n' "$value" | sudo tee "$path" >/dev/null
	fi
}

existing_mount="$(findmnt -t hugetlbfs -n -o TARGET | head -n 1 || true)"

if [[ -n "$existing_mount" ]]; then
	MOUNT_POINT="$existing_mount"
else
	run_root mkdir -p "$MOUNT_POINT"
	run_root mount -t hugetlbfs nodev "$MOUNT_POINT"
fi

current_pages="$(cat "$HUGEPAGES_SYSFS")"
if [[ "$current_pages" -lt "$TARGET_PAGES" ]]; then
	write_root_file "$TARGET_PAGES" "$HUGEPAGES_SYSFS"
fi

echo "Hugepages target: $TARGET_PAGES"
echo "Hugepages current: $(cat "$HUGEPAGES_SYSFS")"
echo "Hugetlbfs mount: $MOUNT_POINT"
