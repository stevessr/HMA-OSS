#!/system/bin/sh
# KernelSU/SukiSU's installer sources customize.sh after extracting MODPATH.
[ -n "$KSU" ] || abort '! Install from SukiSU/KernelSU, not recovery or another root manager'
ABI=$(getprop ro.product.cpu.abi)
[ "$ABI" = "arm64-v8a" ] || abort '! This module requires arm64-v8a; detected: '"$ABI"
SDK=$(getprop ro.build.version.sdk)
case "$SDK" in ''|*[!0-9]*) abort '! Cannot determine Android API level' ;; esac
[ "$SDK" -ge 29 ] || abort '! Android 10 / API 29+ is required'
[ -n "$MODPATH" ] && [ -d "$MODPATH" ] || abort '! KernelSU module extraction failed (MODPATH invalid)'
[ -f "$MODPATH/module.prop" ] || abort '! module.prop missing'
[ -f "$MODPATH/legacy-cleanup.sh" ] || abort '! Legacy cleanup helper missing; use a complete module ZIP'
[ -f "$MODPATH/bin/hma-injector" ] || abort '! Native injector missing'
[ -f "$MODPATH/lib/libhma-payload.so" ] || abort '! Native payload missing'
[ -s "$MODPATH/manager.apk" ] || abort '! HMA-OSS manager APK missing'
[ -f "$MODPATH/manager-apk.sh" ] || abort '! Manager APK helper missing'
[ -f "$MODPATH/webroot/index.html" ] || abort '! KernelSU WebUI missing'

. "$MODPATH/legacy-cleanup.sh" || abort '! Cannot load legacy cleanup helper'
. "$MODPATH/state.sh" || abort '! Cannot load boot state helpers'
# Stop aborting just because the original HMA module exists. Remove it with
# KernelSU's own disable/remove markers; an active hook is unloaded on reboot.
hma_legacy_migrate /data/adb || abort '! Legacy cleanup failed; inspect the installer output'

# Prevent overlapping old/new system_server hooks in the current boot, even if
# someone taps the Action button directly after a successful install.
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
[ -n "$BOOT_ID" ] || abort '! Cannot read boot ID; refusing unsafe hot installation'
# Record process identity too, for devices that use framework-only soft reboot.
BOOT_SERVER_START=$(hma_system_server_start)
printf '%s %s\n' "$BOOT_ID" "$BOOT_SERVER_START" > "$MODPATH/installed_boot_id" ||
  abort '! Cannot write reboot-required marker'

rm -f "$MODPATH/enabled" "$MODPATH/injected_pid" "$MODPATH/injection_failed"
mkdir -p "$MODPATH/log" || abort '! Cannot create module log directory'
set_perm "$MODPATH/bin/hma-injector" 0 0 0755
set_perm "$MODPATH/lib/libhma-payload.so" 0 0 0644
set_perm "$MODPATH/manager.apk" 0 0 0644
ui_print '- Previous HMA-OSS Zygisk module and legacy boot scripts handled automatically.'
ui_print '- HMA settings were preserved; manager APK was not uninstalled.'
ui_print '- REBOOT required before first Action test (no double injection).'
