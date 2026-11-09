#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/module"
mkdir -p "$MOD/bin" "$MOD/lib" "$TMP/mock"
cp "$ROOT/sukisu/module/try-inject.sh" "$ROOT/sukisu/module/state.sh" "$MOD/"
touch "$MOD/lib/libhma-payload.so"
printf '#!/bin/sh\nexit 0\n' > "$MOD/bin/hma-injector"
chmod +x "$MOD/bin/hma-injector"
cat > "$TMP/mock/cat" <<'EOF'
#!/bin/sh
if [ "$1" = /proc/sys/kernel/random/boot_id ]; then
  printf '%s\n' test-boot
else
  exec /bin/cat "$@"
fi
EOF
cat > "$TMP/mock/pidof" <<'EOF'
#!/bin/sh
# A test-only invalid target ensures no actual injection is attempted.
exit 0
EOF
cat > "$TMP/mock/getprop" <<'EOF'
#!/bin/sh
[ "$1" = sys.boot_completed ] && echo 1
EOF
chmod +x "$TMP/mock/cat" "$TMP/mock/pidof" "$TMP/mock/getprop"
run_try() {
  set +e
  TRY_LOG="$(PATH="$TMP/mock:$PATH" sh "$MOD/try-inject.sh" 2>&1)"
  TRY_RC=$?
  set -e
}
printf 'test-boot\n' > "$MOD/injection_failed"
run_try
[ "$TRY_RC" -eq 11 ]
[ -f "$MOD/injection_failed" ]
printf 'previous-boot\n' > "$MOD/injection_failed"
run_try
[ "$TRY_RC" -eq 1 ] # The mocked PID is invalid; stale failure was cleared.
[ ! -e "$MOD/injection_failed" ]
[ ! -e "$MOD/.inject-lock" ]
echo 'Boot-scoped failure recovery tests passed'
