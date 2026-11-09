#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/module"
mkdir -p "$MOD" "$TMP/mock"
cp "$ROOT/sukisu/module/manager-apk.sh" "$MOD/"
printf 'fake-apk' > "$MOD/manager.apk"
cat > "$TMP/mock/cmd" <<'EOF'
#!/bin/sh
[ "$1" = package ] && [ "$2" = path ] || exit 1
[ -f "$HMA_TEST_INSTALLED" ] || exit 0
printf 'package:%s\n' "$HMA_TEST_INSTALLED"
EOF
cat > "$TMP/mock/pm" <<'EOF'
#!/bin/sh
case "$1" in
  path) [ -f "$HMA_TEST_INSTALLED" ] && printf 'package:%s\n' "$HMA_TEST_INSTALLED";;
  install)
    printf '%s\n' "$*" >> "$HMA_TEST_INSTALL_LOG"
    [ ! -f "$HMA_TEST_FAIL" ] || { echo 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'; exit 1; }
    touch "$HMA_TEST_INSTALLED"
    echo Success
    ;;
esac
EOF
chmod +x "$TMP/mock/cmd" "$TMP/mock/pm"
export HMA_TEST_INSTALLED="$TMP/base.apk"
export HMA_TEST_INSTALL_LOG="$TMP/install.log"
export HMA_TEST_FAIL="$TMP/fail"
export PATH="$TMP/mock:$PATH"
MODDIR="$MOD"
. "$MOD/manager-apk.sh"
resolved="$(hma_manager_resolve)"
[ "$resolved" = "$HMA_TEST_INSTALLED" ]
[ "$(wc -l < "$HMA_TEST_INSTALL_LOG")" -eq 1 ]
resolved="$(hma_manager_resolve)"
[ "$resolved" = "$HMA_TEST_INSTALLED" ]
[ "$(wc -l < "$HMA_TEST_INSTALL_LOG")" -eq 1 ]
rm -f "$HMA_TEST_INSTALLED"
touch "$HMA_TEST_FAIL"
if hma_manager_resolve >/dev/null 2>&1; then
  echo 'Signature mismatch was wrongly accepted' >&2
  exit 1
fi
[ ! -f "$HMA_TEST_INSTALLED" ]
[ "$(wc -l < "$HMA_TEST_INSTALL_LOG")" -eq 2 ]
echo 'Bundled APK auto-install, existing app reuse, and signature safety passed'
