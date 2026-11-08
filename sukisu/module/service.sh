#!/system/bin/sh
# Late-start service. Never inject unless the user explicitly opted in.
MODDIR="${0%/*}"
# Never reuse a PID recorded on an earlier boot.
rm -f "$MODDIR/injected_pid"
[ -f "$MODDIR/enabled" ] || exit 0
[ -f "$MODDIR/disable" ] && exit 0
[ -f "$MODDIR/injection_failed" ] && exit 0
i=0
while [ "$i" -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  i=$((i+1))
  sleep 2
done
[ "$(getprop sys.boot_completed)" = "1" ] || exit 0
sh "$MODDIR/try-inject.sh" >> "$MODDIR/log/service.log" 2>&1
