#!/system/bin/sh
MODDIR="${0%/*}"
[ -f "$MODDIR/disable" ] && exit 1
[ -f "$MODDIR/injection_failed" ] && exit 1
[ -x "$MODDIR/bin/hma-injector" ] || exit 1
[ -f "$MODDIR/lib/libhma-payload.so" ] || exit 1
PID=$(pidof system_server | awk '{print $1}')
[ -n "$PID" ] || { echo 'system_server not found'; exit 1; }
[ -f "$MODDIR/injected_pid" ] && [ "$(cat "$MODDIR/injected_pid")" = "$PID" ] && exit 0
APK=$(cmd package path org.frknkrc44.hma_oss 2>/dev/null | sed -n 's/^package:\(.*base\.apk\)$/\1/p' | head -n 1)
[ -f "$APK" ] || { echo 'HMA manager APK not installed'; exit 1; }
# Mark failure before attaching, so an abrupt crash never triggers boot retries.
touch "$MODDIR/injection_failed"
START=$(date +%s)
"$MODDIR/bin/hma-injector" "$PID" "$MODDIR/lib/libhma-payload.so" "$APK"
RESULT=$?
if [ "$RESULT" -ne 0 ]; then
  echo "Native loader failed ($RESULT)"
  rm -f "$MODDIR/enabled"
  exit "$RESULT"
fi
# Native return is asynchronous; require a fresh HMAService workMode=1 status.
COUNT=0
while [ "$COUNT" -lt 30 ]; do
  CURRENT=$(pidof system_server | awk '{print $1}')
  [ "$CURRENT" = "$PID" ] || break
  for STATUS in /data/misc/hide_my_applist_*/status.json; do
    [ -f "$STATUS" ] || continue
    MODIFIED=$(stat -c %Y "$STATUS" 2>/dev/null || echo 0)
    if [ "$MODIFIED" -ge "$START" ] &&
      grep -Eq '"workMode"[[:space:]]*:[[:space:]]*1([^0-9]|$)' "$STATUS"; then
      sleep 5
      [ "$(pidof system_server | awk '{print $1}')" = "$PID" ] || break 2
      echo "$PID" > "$MODDIR/injected_pid"
      rm -f "$MODDIR/injection_failed"
      echo "HMAService reports running in system_server PID $PID"
      exit 0
    fi
  done
  COUNT=$((COUNT+1))
  sleep 1
done
echo 'HMAService did not become healthy; autostart disabled'
rm -f "$MODDIR/enabled"
exit 8
