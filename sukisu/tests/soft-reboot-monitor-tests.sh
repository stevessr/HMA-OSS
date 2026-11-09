#!/usr/bin/env bash
# Full service.sh lifecycle under fake Android properties/processes. Ensures a
# framework-only reboot re-arms an enabled backend with the SAME kernel UUID.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/module"
mkdir -p "$MOD" "$TMP/mock"
cp "$ROOT/sukisu/module/service.sh" "$ROOT/sukisu/module/state.sh" "$MOD/"
cat >> "$MOD/state.sh" <<'EOF'
# The fake system_server processes are not real /proc entries.
hma_process_start() {
  case "$1" in
    4101) echo 701 ;;
    4102) echo 702 ;;
    *) echo 600 ;;
  esac
}
EOF
printf '4101\n' > "$TMP/server-pid"
touch "$MOD/enabled"
cat > "$TMP/mock/pidof" <<'EOF'
#!/bin/sh
[ "$1" = system_server ] && cat "$HMA_TEST_PIDFILE"
EOF
cat > "$TMP/mock/getprop" <<'EOF'
#!/bin/sh
[ "$1" = sys.boot_completed ] && echo 1
EOF
cat > "$TMP/mock/sleep" <<'EOF'
#!/bin/sh
# No real delay in lifecycle test; timeout protects against infinite loops.
exit 0
EOF
cat > "$MOD/try-inject.sh" <<'EOF'
#!/bin/sh
MODDIR="${0%/*}"
n=0
[ ! -f "$MODDIR/injections" ] || n=$(cat "$MODDIR/injections")
n=$((n + 1))
printf '%s\n' "$n" > "$MODDIR/injections"
if [ "$n" -eq 1 ]; then
  # A failed first instance is remembered, but the next framework-only
  # restart can clear it when its process start ticks change.
  boot=$(cat /proc/sys/kernel/random/boot_id)
  printf '%s %s\n' "$boot" 701 > "$MODDIR/injection_failed"
  printf '4102\n' > "$HMA_TEST_PIDFILE"
  exit 8
fi
rm -f "$MODDIR/injection_failed"
touch "$MODDIR/disable"
exit 0
EOF
chmod +x "$TMP/mock/pidof" "$TMP/mock/getprop" "$TMP/mock/sleep"
export HMA_TEST_PIDFILE="$TMP/server-pid"
export PATH="$TMP/mock:$PATH"
timeout 8 sh "$MOD/service.sh"
[ "$(cat "$MOD/injections")" = 2 ]
grep -q 'system_server 4101 (701)' "$MOD/log/service.log"
grep -q 'system_server 4102 (702)' "$MOD/log/service.log"
grep -q 'native injector result: 8' "$MOD/log/service.log"
grep -q 'native injector result: 0' "$MOD/log/service.log"
[ ! -d "$MOD/.monitor-lock" ]
echo 'Framework soft reboot monitor auto-recovery regression passed'
