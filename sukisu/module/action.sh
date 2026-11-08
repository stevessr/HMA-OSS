#!/system/bin/sh
MODDIR="${0%/*}"
[ -f "$MODDIR/disable" ] && { echo 'Module is disabled in SukiSU'; exit 1; }
if [ -f "$MODDIR/enabled" ]; then
  rm -f "$MODDIR/enabled" "$MODDIR/injection_failed"
  echo 'Autostart disabled. An already-loaded hook remains until reboot.'
  exit 0
fi
[ -x "$MODDIR/bin/hma-injector" ] || { echo 'Native backend missing'; exit 1; }
rm -f "$MODDIR/injection_failed"
echo 'Attempting standalone system_server injection (no Zygisk/Riru/Xposed)'
sh "$MODDIR/try-inject.sh"
RESULT=$?
if [ "$RESULT" -eq 0 ]; then
  touch "$MODDIR/enabled"
  echo 'Loader returned success; autostart enabled. VERIFY HMA service separately.'
else
  echo 'Test failed; autostart remains disabled.'
fi
exit "$RESULT"
