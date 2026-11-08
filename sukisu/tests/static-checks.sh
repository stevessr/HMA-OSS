#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for file in "$ROOT"/sukisu/module/*.sh; do
  sh -n "$file"
done
bash -n "$ROOT/sukisu/package.sh"
grep -qx 'id=hma_sukisu' "$ROOT/sukisu/module/module.prop"
grep -q 'AttachCurrentThread' "$ROOT/sukisu/native/payload.cpp"
grep -q 'PTRACE_ATTACH' "$ROOT/sukisu/native/injector.cpp"
! grep -qi 'ZygoteLoader' "$ROOT/app/build.gradle.kts"
echo 'SukiSU static checks passed'
