#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/sukisu/module/state.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
printf 'unit-boot\n' > "$TEMP/installed_boot_id"
hma_install_reboot_pending "$TEMP/installed_boot_id" unit-boot
[ -f "$TEMP/installed_boot_id" ]
! hma_install_reboot_pending "$TEMP/installed_boot_id" next-boot
[ ! -e "$TEMP/installed_boot_id" ]
! hma_install_reboot_pending "$TEMP/installed_boot_id" next-boot

# Exercise lock helper BEFORE any other function so nested function definitions fail.
hma_acquire_lock "$TEMP/early-lock" boot-A
hma_release_lock "$TEMP/early-lock"
printf 'boot-A 123 456\n' > "$TEMP/marker"
hma_pid_marker_matches "$TEMP/marker" boot-A 123 456
! hma_pid_marker_matches "$TEMP/marker" boot-B 123 456
! hma_pid_marker_matches "$TEMP/marker" boot-A 124 456
! hma_pid_marker_matches "$TEMP/marker" boot-A 123 457
! hma_pid_marker_matches "$TEMP/missing" boot-A 123 456

hma_acquire_lock "$TEMP/lock" boot-A
! hma_acquire_lock "$TEMP/lock" boot-A
# A new boot may safely reclaim a lock left behind by a killed process.
hma_acquire_lock "$TEMP/lock" boot-B
! hma_acquire_lock "$TEMP/lock" boot-B
hma_release_lock "$TEMP/lock"
hma_acquire_lock "$TEMP/lock" boot-B
hma_release_lock "$TEMP/lock"

printf '{ "workMode": 1, "managerUid": 10001 }\n' > "$TEMP/status.json"
touch -d '@1100' "$TEMP/status.json"
hma_workmode_ok "$TEMP/status.json"
hma_fresh_workmode_ok "$TEMP/status.json" 1099
! hma_fresh_workmode_ok "$TEMP/status.json" 1100
! hma_fresh_workmode_ok "$TEMP/status.json" 1101
printf '{ "workMode": 10 }\n' > "$TEMP/status.json"
touch -d '@1102' "$TEMP/status.json"
! hma_workmode_ok "$TEMP/status.json"
printf '{ "workMode": 1, "managerUid": -1 }\n' > "$TEMP/status.json"
! hma_workmode_ok "$TEMP/status.json"
printf '{ "workMode": 1 }\n' > "$TEMP/status.json"
! hma_workmode_ok "$TEMP/status.json"
printf '{ "workMode": 2 }\n' > "$TEMP/status.json"
! hma_fresh_workmode_ok "$TEMP/status.json" 1100
echo 'SukiSU process identity and fresh service-state tests passed'
