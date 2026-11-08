#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/module"
mkdir -p "$MOD/bin" "$TMP/mock"
cp "$ROOT/sukisu/module/action.sh" "$ROOT/sukisu/module/state.sh" "$MOD/"
touch "$MOD/bin/hma-injector"
chmod +x "$MOD/bin/hma-injector"

# Fake only boot identity; no system files are modified and no injector runs.
cat > "$TMP/mock/cat" <<'EOF'
#!/bin/sh
if [ "$1" = "/proc/sys/kernel/random/boot_id" ]; then
  printf '%s\n' "$HMA_TEST_BOOT_ID"
else
  exec /bin/cat "$@"
fi
EOF
chmod +x "$TMP/mock/cat"
cat > "$MOD/try-inject.sh" <<'EOF'
#!/bin/sh
MODDIR="${0%/*}"
[ ! -f "$MODDIR/injection_failed" ] || exit 23
touch "$MODDIR/fake-inject-called"
exit 0
EOF

run_action() {
  set +e
  ACTION_OUTPUT="$(HMA_TEST_BOOT_ID=unit-boot PATH="$TMP/mock:$PATH" sh "$MOD/action.sh" 2>&1)"
  ACTION_RC=$?
  set -e
}

# A failed native attempt in the current boot is never retried.
printf 'unit-boot\n' > "$MOD/injection_failed"
run_action
[ "$ACTION_RC" -eq 11 ]
[ ! -e "$MOD/enabled" ]
[ ! -e "$MOD/fake-inject-called" ]

# Old-boot markers can only be cleared by explicitly pressing Action.
printf 'previous-boot\n' > "$MOD/injection_failed"
run_action
[ "$ACTION_RC" -eq 0 ]
[ -f "$MOD/enabled" ]
[ -f "$MOD/fake-inject-called" ]
[ ! -f "$MOD/injection_failed" ]

# A second press disables the next-boot retry and releases the lock.
run_action
[ "$ACTION_RC" -eq 0 ]
[ ! -f "$MOD/enabled" ]
[ ! -d "$MOD/.inject-lock" ]

# An active injection lock prevents toggling autostart.
touch "$MOD/enabled"
mkdir "$MOD/.inject-lock"
printf 'unit-boot\n' > "$MOD/.inject-lock/boot"
run_action
[ "$ACTION_RC" -eq 10 ]
[ -f "$MOD/enabled" ]
rm -rf "$MOD/.inject-lock"

# A stale lock from a previous boot may be reclaimed.
mkdir "$MOD/.inject-lock"
printf 'previous-boot\n' > "$MOD/.inject-lock/boot"
run_action
[ "$ACTION_RC" -eq 0 ]
[ ! -f "$MOD/enabled" ]
[ ! -d "$MOD/.inject-lock" ]

# A failing backend never enables autostart.
rm -f "$MOD/fake-inject-called"
printf '#!/bin/sh\nexit 9\n' > "$MOD/try-inject.sh"
run_action
[ "$ACTION_RC" -eq 9 ]
[ ! -f "$MOD/enabled" ]

# A disabled SukiSU module never executes injection or changes state.
touch "$MOD/disable"
run_action
[ "$ACTION_RC" -eq 1 ]
[ ! -f "$MOD/enabled" ]
echo 'SukiSU Action state transitions passed'
