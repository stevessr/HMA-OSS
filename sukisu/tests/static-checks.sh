#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for file in "$ROOT"/sukisu/module/*.sh; do
  sh -n "$file"
done
bash -n "$ROOT/sukisu/package.sh"
bash -n "$ROOT/sukisu/tests/state-tests.sh"
bash -n "$ROOT/sukisu/tests/action-tests.sh"
bash -n "$ROOT/sukisu/tests/legacy-migration-tests.sh"
bash "$ROOT/sukisu/tests/state-tests.sh"
bash "$ROOT/sukisu/tests/action-tests.sh"
bash "$ROOT/sukisu/tests/legacy-migration-tests.sh"
grep -qx 'id=hma_sukisu' "$ROOT/sukisu/module/module.prop"
grep -q 'AttachCurrentThread' "$ROOT/sukisu/native/payload.cpp"
grep -q 'PTRACE_ATTACH' "$ROOT/sukisu/native/injector.cpp"
grep -q 'hma_acquire_lock "$LOCKDIR"' "$ROOT/sukisu/module/try-inject.sh"
grep -q 'hma_pid_marker_matches' "$ROOT/sukisu/module/try-inject.sh"
! grep -qi 'ZygoteLoader' "$ROOT/app/build.gradle.kts"
echo 'SukiSU static checks passed'
