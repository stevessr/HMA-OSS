#!/system/bin/sh
MODDIR="${0%/*}"
. "$MODDIR/state.sh" || exit 1
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || { echo 'Cannot read boot ID'; exit 1; }
if hma_install_reboot_pending "$MODDIR/installed_boot_id" "$BOOT_ID" "$(hma_system_server_start)"; then
  echo 'Reboot required after installation/migration before enabling HMA hooks.'
  exit 12
fi
[ -f "$MODDIR/disable" ] && { echo 'Module is disabled in SukiSU'; exit 1; }

# Disabling autostart must not race an active system_server injection.
if [ -f "$MODDIR/enabled" ]; then
  LOCKDIR="$MODDIR/.inject-lock"
  hma_acquire_lock "$LOCKDIR" "$BOOT_ID" || {
    echo 'Injection in progress; retry Action after it finishes'
    exit 10
  }
  rm -f "$MODDIR/enabled"
  hma_release_lock "$LOCKDIR"
  echo 'Autostart disabled. Loaded hooks remain until reboot.'
  exit 0
fi

if [ -f "$MODDIR/injection_failed" ]; then
  FAILED_BOOT=$(cat "$MODDIR/injection_failed" 2>/dev/null)
  if [ "$FAILED_BOOT" = "$BOOT_ID" ]; then
    echo 'This boot had a failed or interrupted injection. Reboot before retrying.'
    exit 11
  fi
  # Explicit Action invocation on a new boot is the only retry mechanism.
  rm -f "$MODDIR/injection_failed" || exit 1
fi

[ -x "$MODDIR/bin/hma-injector" ] || { echo 'Native backend missing'; exit 1; }
echo 'Testing standalone system_server backend (no third-party injector)'
sh "$MODDIR/try-inject.sh"
RESULT=$?
if [ "$RESULT" -eq 0 ]; then
  touch "$MODDIR/enabled" || exit 1
  echo 'HMAService was verified; next-boot autostart enabled.'
else
  echo 'Test failed; autostart remains disabled.'
fi
exit "$RESULT"
