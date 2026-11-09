#!/system/bin/sh
# Manual/boot injector, serialized so SukiSU actions cannot race boot services.
MODDIR="${0%/*}"
. "$MODDIR/state.sh" || exit 1
[ -f "$MODDIR/disable" ] && { echo 'Module is disabled'; exit 1; }
# A failure lock is boot-scoped, not a permanent installation lock.
[ -x "$MODDIR/bin/hma-injector" ] || { echo 'Native injector missing'; exit 1; }
[ -f "$MODDIR/lib/libhma-payload.so" ] || { echo 'JNI payload missing'; exit 1; }

BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || { echo 'Cannot read boot ID'; exit 1; }
if hma_install_reboot_pending "$MODDIR/injection_failed" "$BOOT_ID" "$(hma_system_server_start)"; then
  echo 'Native injection failed in this system_server instance; restart Android before retry'
  exit 11
fi
if hma_install_reboot_pending "$MODDIR/installed_boot_id" "$BOOT_ID" "$(hma_system_server_start)"; then
  echo 'Reboot required before injecting the standalone HMA backend'
  exit 12
fi
LOCKDIR="$MODDIR/.inject-lock"
if ! hma_acquire_lock "$LOCKDIR" "$BOOT_ID"; then
  echo 'An injection attempt is already running or has an uncleared lock'
  exit 10
fi
trap 'hma_release_lock "$LOCKDIR"' EXIT
trap 'exit 130' INT TERM HUP

PID=$(pidof system_server | awk '{print $1}')
case "$PID" in ''|*[!0-9]*) echo 'Cannot find a valid system_server PID'; exit 1 ;; esac
START_TICKS=$(hma_process_start "$PID")
[ -n "$START_TICKS" ] || {
  echo 'Cannot establish target process identity'
  exit 1
}

# A previously verified injection in this exact process must never be repeated.
if hma_pid_marker_matches "$MODDIR/injected_pid" "$BOOT_ID" "$PID" "$START_TICKS"; then
  for STATUS in /data/misc/hide_my_applist_*/status.json; do
    if hma_workmode_ok "$STATUS"; then
      echo "Already injected and verified for system_server PID $PID"
      exit 0
    fi
  done
  echo 'Previously injected process is unhealthy; reboot before retrying'
  exit 9
fi

# The ZIP already contains manager.apk. PackageManager will not expose its
# path until the manager app is installed; install from our bundled file when
# absent, before attaching to system_server.
. "$MODDIR/manager-apk.sh" || exit 1
APK=$(hma_manager_resolve) || {
  echo 'Cannot resolve the HMA manager. Open the SukiSU module WebUI to install it.'
  exit 13
}
[ -r "$APK" ] || { echo 'Resolved manager path is unreadable'; exit 13; }

# mtime is in whole seconds on common Android stat implementations. Deliberately
# cross a second boundary to exclude a workMode=1 left by a previous boot/load.
BASELINE=$(date +%s)
sleep 2
[ "$(pidof system_server | awk '{print $1}')" = "$PID" ] &&
  [ "$(hma_process_start "$PID")" = "$START_TICKS" ] || {
  echo 'system_server restarted before the attempt'
  exit 1
}

# Persist failure BEFORE attaching: a system_server crash cannot cause boot loops.
printf '%s %s\n' "$BOOT_ID" "$START_TICKS" > "$MODDIR/injection_failed" || exit 1
"$MODDIR/bin/hma-injector" "$PID" "$MODDIR/lib/libhma-payload.so" "$APK"
RESULT=$?
if [ "$RESULT" -ne 0 ]; then
  echo "Native loader failed ($RESULT); do not retry in this boot"
  rm -f "$MODDIR/enabled"
  exit "$RESULT"
fi

COUNT=0
while [ "$COUNT" -lt 45 ]; do
  [ "$(pidof system_server | awk '{print $1}')" = "$PID" ] &&
    [ "$(hma_process_start "$PID")" = "$START_TICKS" ] || break
  for STATUS in /data/misc/hide_my_applist_*/status.json; do
    if hma_fresh_workmode_ok "$STATUS" "$BASELINE"; then
      sleep 5
      [ "$(pidof system_server | awk '{print $1}')" = "$PID" ] &&
        [ "$(hma_process_start "$PID")" = "$START_TICKS" ] || break 2
      MARKER_TMP="$MODDIR/injected_pid.$$"
      if printf '%s %s %s\n' "$BOOT_ID" "$PID" "$START_TICKS" > "$MARKER_TMP" &&
        mv -f "$MARKER_TMP" "$MODDIR/injected_pid"; then
        rm -f "$MODDIR/injection_failed"
        echo "HMAService verified in system_server PID $PID"
        exit 0
      fi
      rm -f "$MARKER_TMP"
      break 2
    fi
  done
  COUNT=$((COUNT + 1))
  sleep 1
done
echo 'No fresh healthy HMAService handshake; autostart disabled, reboot required'
rm -f "$MODDIR/enabled"
exit 8
