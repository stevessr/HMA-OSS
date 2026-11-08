#!/system/bin/sh
# Only the original HMA-OSS Zygisk module and its known external boot scripts.
# Never erase /data/misc/hide_my_applist_* or uninstall the manager APK.
hma_legacy_log() {
  if command -v ui_print >/dev/null 2>&1; then
    ui_print "$1"
  else
    echo "$1"
  fi
}

hma_legacy_cleanup_scripts() {
  hma_root="$1"
  for hma_hook_dir in post-fs-data.d post-mount.d boot-completed.d; do
    hma_hook="$hma_root/$hma_hook_dir/hmaoss.sh"
    # Do not follow links or delete another module's similarly named script.
    if [ -L "$hma_hook" ]; then
      hma_legacy_log "! Keeping unexpected symlink: $hma_hook"
      continue
    fi
    if [ -f "$hma_hook" ]; then
      if grep -Fq 'hma_oss_zygisk' "$hma_hook" &&
        grep -Fq 'module.prop' "$hma_hook"; then
        rm -f "$hma_hook" || return 1
        hma_legacy_log "- Removed legacy HMA boot hook: $hma_hook_dir/hmaoss.sh"
      else
        hma_legacy_log "! Kept unrelated boot script: $hma_hook"
      fi
    fi
    # Shared boot-hook directory is removed only when empty.
    rmdir "$hma_root/$hma_hook_dir" 2>/dev/null || :
  done
  return 0
}

hma_legacy_migrate() {
  hma_root="$1"
  HMA_LEGACY_FOUND=0
  for hma_stage in modules modules_update; do
    hma_old="$hma_root/$hma_stage/hma_oss_zygisk"
    [ -e "$hma_old" ] || [ -L "$hma_old" ] || continue
    if [ -L "$hma_old" ] || [ ! -d "$hma_old" ]; then
      hma_legacy_log "! Refusing unexpected legacy module path: $hma_old"
      return 1
    fi
    hma_prop="$hma_old/module.prop"
    if [ ! -f "$hma_prop" ] && [ -f "$hma_old/module.prop.bak" ]; then
      hma_prop="$hma_old/module.prop.bak"
    fi
    # Do not alter another module or a malformed path masquerading as HMA.
    if [ -L "$hma_prop" ] || ! grep -qx 'id=hma_oss_zygisk' "$hma_prop" 2>/dev/null; then
      hma_legacy_log "! Cannot verify old HMA module identity: $hma_old"
      return 1
    fi
    # Official KernelSU flags. A reboot removes the old module safely.
    # Do not execute the old uninstall.sh or delete loaded files in this boot.
    touch "$hma_old/disable" || return 1
    touch "$hma_old/remove" || return 1
    HMA_LEGACY_FOUND=1
    hma_legacy_log "- Disabled old HMA-OSS Zygisk ($hma_stage); removal scheduled on reboot"
  done
  hma_legacy_cleanup_scripts "$hma_root" || return 1
}
