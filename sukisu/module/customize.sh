#!/system/bin/sh
# SukiSU / KernelSU module installer: reject unknown root environments.
[ -n "$KSU" ] || abort '! SukiSU/KernelSU environment required (KSU is unset)'
ABI=$(getprop ro.product.cpu.abi)
[ "$ABI" = "arm64-v8a" ] || abort '! Native backend supports arm64-v8a only'
SDK=$(getprop ro.build.version.sdk)
case "$SDK" in ''|*[!0-9]*) abort '! Android SDK level cannot be determined' ;; esac
[ "$SDK" -ge 29 ] || abort '! Native backend requires Android 10 (API 29) or newer'
[ -f "$MODPATH/bin/hma-injector" ] || abort '! Native injector is missing'
[ -f "$MODPATH/lib/libhma-payload.so" ] || abort '! Native payload is missing'
[ -f "$MODPATH/manager.apk" ] || abort '! HMA-OSS manager APK is missing'
# Running the old backend alongside this one can double-hook system_server.
for OLD in /data/adb/modules/hma_oss_zygisk /data/adb/modules_update/hma_oss_zygisk; do
  [ -d "$OLD" ] && abort '! Remove the old hma_oss_zygisk module and reboot before installing'
done
rm -f "$MODPATH/enabled" "$MODPATH/injected_pid" "$MODPATH/injection_failed"
mkdir -p "$MODPATH/log"
set_perm "$MODPATH/bin/hma-injector" 0 0 0755
set_perm "$MODPATH/lib/libhma-payload.so" 0 0 0644
set_perm "$MODPATH/manager.apk" 0 0 0644
ui_print '- Experimental SukiSU backend installed, but not enabled.'
ui_print '- Install the bundled manager APK. Use Action for an explicit first test.'
