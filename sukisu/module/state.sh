#!/system/bin/sh
# Shared fail-closed state checks. This file only defines functions.
# An install/migration cannot be hot-activated within the same boot.
# Return process start ticks for the current system_server. Android's soft
# reboot restarts this process without changing the kernel boot ID.
hma_system_server_start() {
  hma_server_pid=$(pidof system_server 2>/dev/null | awk '{print $1}')
  case "$hma_server_pid" in ''|*[!0-9]*) return 1 ;; esac
  hma_process_start "$hma_server_pid"
}

# Module may have been installed in the same kernel boot but an Android
# framework soft reboot has since replaced system_server. Legacy one-field
# markers are also accepted for upgrades from earlier experimental builds.
hma_install_reboot_pending() {
  [ -e "$1" ] || return 1
  [ -r "$1" ] || return 0
  hma_marker_boot='' hma_marker_start=''
  IFS=' ' read -r hma_marker_boot hma_marker_start < "$1" || return 0
  [ -n "$hma_marker_boot" ] || return 0
  if [ "$hma_marker_boot" != "$2" ]; then
    rm -f "$1" || return 0
    return 1
  fi
  # The same kernel may host a fresh system_server after a framework restart.
  if [ -n "$hma_marker_start" ] && [ -n "$3" ] &&
     [ "$hma_marker_start" != "$3" ]; then
    rm -f "$1" || return 0
    return 1
  fi
  # Older builds wrote just a boot ID. If kernel boot time is strictly newer
  # than the persisted marker timestamp, a full reboot has occurred.
  # This fallback never unlocks a marker merely because time elapsed.
  hma_boot_epoch=$(awk '$1 == "btime" { print $2; exit }' /proc/stat 2>/dev/null)
  hma_marker_time=$(stat -c %Y "$1" 2>/dev/null)
  case "$hma_boot_epoch:$hma_marker_time" in
    *[!0-9:]*|:*|*:) return 0 ;;
  esac
  if [ "$hma_marker_time" -lt "$hma_boot_epoch" ]; then
    rm -f "$1" || return 0
    return 1
  fi
  return 0
}

hma_process_start() {
  # /proc/PID/stat field 22, relative to the first field after "(comm)".
  sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
}

hma_pid_marker_matches() {
  [ -r "$1" ] || return 1
  local_boot='' local_pid='' local_start=''
  IFS=' ' read -r local_boot local_pid local_start < "$1" || return 1
  [ -n "$local_boot" ] && [ -n "$local_start" ] &&
    [ "$local_boot" = "$2" ] && [ "$local_pid" = "$3" ] &&
    [ "$local_start" = "$4" ]
}

# Atomically lock operations. A lock abandoned on a previous boot is safe to
# discard; never steal one created in the current boot.
hma_acquire_lock() {
  lock_path="$1" lock_boot="$2"
  if mkdir "$lock_path" 2>/dev/null; then
    printf '%s\n' "$lock_boot" > "$lock_path/boot" || {
      rmdir "$lock_path" 2>/dev/null || true
      return 1
    }
    return 0
  fi
  [ -r "$lock_path/boot" ] || return 1
  [ "$(cat "$lock_path/boot" 2>/dev/null)" != "$lock_boot" ] || return 1
  rm -f "$lock_path/boot" || return 1
  rmdir "$lock_path" 2>/dev/null || return 1
  mkdir "$lock_path" 2>/dev/null || return 1
  printf '%s\n' "$lock_boot" > "$lock_path/boot" || return 1
}

hma_release_lock() {
  rm -f "$1/boot"
  rmdir "$1" 2>/dev/null || true
}

hma_workmode_ok() {
  [ -r "$1" ] &&
    grep -Eq '"workMode"[[:space:]]*:[[:space:]]*1([^0-9]|$)' "$1" &&
    grep -Eq '"managerUid"[[:space:]]*:[[:space:]]*[1-9][0-9]*([^0-9]|$)' "$1"
}

hma_fresh_workmode_ok() {
  [ -r "$1" ] || return 1
  file_time=$(stat -c %Y "$1" 2>/dev/null) || return 1
  case "$file_time" in ''|*[!0-9]*) return 1 ;; esac
  [ "$file_time" -gt "$2" ] && hma_workmode_ok "$1"
}
