#!/system/bin/sh
MODDIR="${0%/*}"
rm -f "$MODDIR/enabled" "$MODDIR/injected_pid" "$MODDIR/injection_failed"
# HMA's persistent /data/misc configuration is intentionally retained.
