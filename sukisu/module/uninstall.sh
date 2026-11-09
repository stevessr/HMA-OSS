#!/system/bin/sh
# Restore module-controlled state without deleting persistent user HMA settings.
MODDIR="${0%/*}"
rm -f "$MODDIR/enabled" "$MODDIR/injected_pid" "$MODDIR/injection_failed" \
  "$MODDIR/installed_boot_id" "$MODDIR/attempt_budget" "$MODDIR/injected_pid."*
if [ -d "$MODDIR/.monitor-lock" ]; then
  # No active monitor should be running during final module removal. KernelSU
  # removes this module directory; do not touch arbitrary external paths.
  rm -f "$MODDIR/.monitor-lock/owner"
  rmdir "$MODDIR/.monitor-lock" 2>/dev/null || :
fi
if [ -d "$MODDIR/.inject-lock" ]; then
  rm -f "$MODDIR/.inject-lock/boot"
  rmdir "$MODDIR/.inject-lock" 2>/dev/null || :
fi
# Earlier HMA versions put their hook outside the module's own directory.
# Remove only scripts positively identified as belonging to old HMA.
if [ -f "$MODDIR/legacy-cleanup.sh" ]; then
  . "$MODDIR/legacy-cleanup.sh"
  hma_legacy_cleanup_scripts /data/adb || :
fi
# The module manager removes the module directory. Never delete HMA configs
# (/data/misc/hide_my_applist_*), unrelated /data/adb entries or app data.
echo 'HMA module cleanup complete; reboot to unload any active hooks.'
