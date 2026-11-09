#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UI="$ROOT/sukisu/module/webroot"
test -s "$UI/index.html"
test -s "$UI/app.js"
test -s "$UI/style.css"
grep -Fq 'webui-api.sh' "$UI/app.js"
grep -Fq 'window.ksu.exec' "$UI/app.js"
grep -Fq "archive: false" "$ROOT/.github/workflows/sukisu.yml"
grep -Fq 'cp -R "$ROOT/sukisu/module/." "$STAGE/"' "$ROOT/sukisu/package.sh"
for command in status install start stop logs; do
  grep -Eq "^[[:space:]]*$command\\)" "$ROOT/sukisu/module/webui-api.sh" || {
    echo "Missing WebUI operation: $command" >&2
    exit 1
  }
done
echo 'KernelSU WebUI resources and direct non-archived ZIP upload checks passed'
