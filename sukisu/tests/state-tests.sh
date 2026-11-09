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

# A framework-only restart changes system_server's start ticks without
# changing the kernel UUID, and must clear the reboot gate.
printf 'same-kernel 123\n' > "$TEMP/installed_boot_id"
hma_install_reboot_pending "$TEMP/installed_boot_id" same-kernel 123
[ -f "$TEMP/installed_boot_id" ]
! hma_install_reboot_pending "$TEMP/installed_boot_id" same-kernel 124
[ ! -f "$TEMP/installed_boot_id" ]

# The same fail-closed check works for the native failure lock marker.
printf 'kernel-Z 555\n' > "$TEMP/injection_failed"
hma_install_reboot_pending "$TEMP/injection_failed" kernel-Z 555
! hma_install_reboot_pending "$TEMP/injection_failed" kernel-Z 556
[ ! -f "$TEMP/injection_failed" ]

# Old one-field markers still preserve same-boot lockouts; new boots clear.
printf 'old-kernel\n' > "$TEMP/installed_boot_id"
hma_install_reboot_pending "$TEMP/installed_boot_id" old-kernel 123
! hma_install_reboot_pending "$TEMP/installed_boot_id" different-kernel 123

# Same-kernel framework restart must reclaim a dead system_server's
# injection lock, while it must never steal from the same process instance.
hma_acquire_lock "$TEMP/soft-lock" boot-F 4101 701
! hma_acquire_lock "$TEMP/soft-lock" boot-F 4101 701
hma_acquire_lock "$TEMP/soft-lock" boot-F 4102 702
! hma_acquire_lock "$TEMP/soft-lock" boot-F 4102 702
hma_release_lock "$TEMP/soft-lock"
mkdir "$TEMP/legacy-lock"
printf 'boot-F\n' > "$TEMP/legacy-lock/boot"
! hma_acquire_lock "$TEMP/legacy-lock" boot-F 4102 702

# Native attach attempts are bounded, but a healthy handshake resets budget.
hma_record_native_attempt "$TEMP/budget" boot-F
hma_record_native_attempt "$TEMP/budget" boot-F
! hma_record_native_attempt "$TEMP/budget" boot-F
[ "$(awk '{print $3}' "$TEMP/budget")" = 2 ]
rm -f "$TEMP/budget"
hma_record_native_attempt "$TEMP/budget" boot-F
hma_record_native_attempt "$TEMP/budget" boot-G
[ "$(awk '{print $3}' "$TEMP/budget")" = 1 ]

# Only one live monitor may observe a boot, and dead-owner lock is reclaimable.
hma_monitor_lock "$TEMP/monitor" boot-F
! hma_monitor_lock "$TEMP/monitor" boot-F
hma_monitor_release "$TEMP/monitor"
mkdir "$TEMP/monitor"
printf 'boot-F 999999 1\n' > "$TEMP/monitor/owner"
hma_monitor_lock "$TEMP/monitor" boot-F
hma_monitor_release "$TEMP/monitor"

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
