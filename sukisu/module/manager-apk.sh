#!/system/bin/sh
# Find the actual installed manager package; if it is absent, safely install
# the APK shipped inside this root module. Never uninstall or wipe app data.
hma_manager_installed_apk() {
  hma_paths=$(cmd package path org.frknkrc44.hma_oss 2>/dev/null)
  [ -n "$hma_paths" ] || hma_paths=$(pm path org.frknkrc44.hma_oss 2>/dev/null)
  hma_apk=$(printf '%s\n' "$hma_paths" |
    sed -n 's/^package:\(.*base\.apk\)$/\1/p' | head -n 1)
  [ -n "$hma_apk" ] && [ -r "$hma_apk" ] || return 1
  printf '%s\n' "$hma_apk"
}

hma_manager_install() {
  if [ ! -s "$MODDIR/manager.apk" ]; then
    echo 'Bundled manager.apk is genuinely missing from the module.' >&2
    return 1
  fi
  echo 'Installing bundled HMA manager APK without removing existing app data...' >&2
  # Android PackageManager handles signing checks. Do NOT uninstall an
  # incompatible manager, bypass its signing check, or clear user data.
  if ! pm install -r "$MODDIR/manager.apk" >&2; then
    echo 'Install failed (possibly different APK signing certificate).' >&2
    echo 'Use the module WebUI to inspect the error; back up before manual migration.' >&2
    return 1
  fi
  return 0
}

hma_manager_resolve() {
  hma_result=$(hma_manager_installed_apk) && {
    printf '%s\n' "$hma_result"
    return 0
  }
  echo 'Android does not report an installed manager; trying bundled manager.apk' >&2
  hma_manager_install || return 1
  hma_manager_installed_apk || {
    echo 'Manager installed but PackageManager still does not expose its APK path.' >&2
    return 1
  }
}
