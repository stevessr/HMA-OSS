#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/sukisu/module/state.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
printf 'boot-A 123 456\n' > "$TEMP/marker"
hma_pid_marker_matches "$TEMP/marker" boot-A 123 456
! hma_pid_marker_matches "$TEMP/marker" boot-B 123 456
! hma_pid_marker_matches "$TEMP/marker" boot-A 124 456
! hma_pid_marker_matches "$TEMP/marker" boot-A 123 457
! hma_pid_marker_matches "$TEMP/missing" boot-A 123 456

printf '{ "workMode": 1, "managerUid": 10001 }\n' > "$TEMP/status.json"
touch -d '@1100' "$TEMP/status.json"
hma_workmode_ok "$TEMP/status.json"
hma_fresh_workmode_ok "$TEMP/status.json" 1099
! hma_fresh_workmode_ok "$TEMP/status.json" 1100
! hma_fresh_workmode_ok "$TEMP/status.json" 1101
printf '{ "workMode": 10 }\n' > "$TEMP/status.json"
touch -d '@1102' "$TEMP/status.json"
! hma_workmode_ok "$TEMP/status.json"
printf '{ "workMode": 2 }\n' > "$TEMP/status.json"
! hma_fresh_workmode_ok "$TEMP/status.json" 1100
echo 'SukiSU process identity and fresh service-state tests passed'
