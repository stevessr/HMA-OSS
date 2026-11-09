#!/system/bin/sh
# Lightweight resident monitor. KernelSU service.sh is normally invoked only
# at boot, not every framework-only ("soft") reboot. Stay alive to recognize
# a NEW system_server and restore the opted-in backend once it is stable.
MODDIR="${0%/*}"
. "$MODDIR/state.sh" || exit 1
[ -f "$MODDIR/disable" ] && exit 0
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || exit 1
mkdir -p "$MODDIR/log" || exit 1

WATCH_LOCK="$MODDIR/.monitor-lock"
if ! hma_monitor_lock "$WATCH_LOCK" "$BOOT_ID"; then
  echo 'Another HMA soft-reboot monitor is already active' >> "$MODDIR/log/service.log"
  exit 0
fi
trap 'hma_monitor_release "$WATCH_LOCK"' EXIT
trap 'exit 0' TERM HUP INT

LAST_SEEN='' LAST_ATTEMPT='' STABLE=0
while [ ! -f "$MODDIR/disable" ]; do
  if [ ! -f "$MODDIR/enabled" ] ||
     [ "$(getprop sys.boot_completed)" != '1' ]; then
    LAST_SEEN='' LAST_ATTEMPT='' STABLE=0
    sleep 12
    continue
  fi

  PID=$(pidof system_server 2>/dev/null | awk '{print $1}')
  case "$PID" in ''|*[!0-9]*) sleep 10; continue ;; esac
  START_TICKS=$(hma_process_start "$PID")
  [ -n "$START_TICKS" ] || { sleep 10; continue; }
  IDENTITY="$BOOT_ID $PID $START_TICKS"
  if [ "$IDENTITY" != "$LAST_SEEN" ]; then
    LAST_SEEN="$IDENTITY"
    STABLE=0
    sleep 6
    continue
  fi
  STABLE=$((STABLE + 1))
  if [ "$STABLE" -lt 2 ]; then
    sleep 6
    continue
  fi
  [ "$IDENTITY" != "$LAST_ATTEMPT" ] || { sleep 12; continue; }

  # If it was already injected into this EXACT process, never attach again.
  if hma_pid_marker_matches "$MODDIR/injected_pid" "$BOOT_ID" "$PID" "$START_TICKS"; then
    LAST_ATTEMPT="$IDENTITY"
    sleep 12
    continue
  fi
  if hma_install_reboot_pending "$MODDIR/installed_boot_id" "$BOOT_ID" "$START_TICKS" ||
     hma_install_reboot_pending "$MODDIR/injection_failed" "$BOOT_ID" "$START_TICKS"; then
    LAST_ATTEMPT="$IDENTITY"
    sleep 12
    continue
  fi

  LAST_ATTEMPT="$IDENTITY"
  printf '\n[%s] system_server %s (%s): attempting opted-in recovery\n' \
    "$(date)" "$PID" "$START_TICKS" >> "$MODDIR/log/service.log"
  sh "$MODDIR/try-inject.sh" >> "$MODDIR/log/service.log" 2>&1
  RESULT=$?
  printf '[%s] native injector result: %s\n' "$(date)" "$RESULT" >> "$MODDIR/log/service.log"
  # PackageManager may not be ready during a soft reboot. There was no native
  # attach for these preflight results, so retry after a longer grace period.
  if [ "$RESULT" -eq 13 ] || [ "$RESULT" -eq 14 ]; then
    LAST_ATTEMPT=''
    sleep 30
  else
    sleep 12
  fi
done
