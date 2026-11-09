#!/system/bin/sh
# Boot-time entry: autostart is opt-in and every attempt is fail-closed.
MODDIR="${0%/*}"
[ -f "$MODDIR/enabled" ] || exit 0
[ -f "$MODDIR/disable" ] && exit 0
# try-inject.sh handles failure markers by boot ID, not file existence.

i=0
while [ "$i" -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  i=$((i + 1))
  sleep 2
done
[ "$(getprop sys.boot_completed)" = "1" ] || exit 0
mkdir -p "$MODDIR/log" || exit 1
sh "$MODDIR/try-inject.sh" >> "$MODDIR/log/service.log" 2>&1
