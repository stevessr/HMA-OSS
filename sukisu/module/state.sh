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
  hma_lock_path="$1" hma_lock_boot="$2"
  hma_lock_pid="${3:-}" hma_lock_start="${4:-}"
  if mkdir "$hma_lock_path" 2>/dev/null; then
    printf '%s %s %s\n' "$hma_lock_boot" "$hma_lock_pid" "$hma_lock_start" > "$hma_lock_path/boot" || {
      rm -f "$hma_lock_path/boot"
      rmdir "$hma_lock_path" 2>/dev/null || true
      return 1
    }
    return 0
  fi
  [ -r "$hma_lock_path/boot" ] || return 1
  hma_old_boot='' hma_old_pid='' hma_old_start=''
  IFS=' ' read -r hma_old_boot hma_old_pid hma_old_start < "$hma_lock_path/boot" || return 1
  if [ "$hma_old_boot" = "$hma_lock_boot" ]; then
    # Only reclaim a lock from a DIFFERENT, fully identified system_server
    # instance. Legacy same-boot lock files remain fail-closed.
    [ -n "$hma_lock_pid" ] && [ -n "$hma_lock_start" ] &&
      [ -n "$hma_old_pid" ] && [ -n "$hma_old_start" ] || return 1
    [ "$hma_old_pid" != "$hma_lock_pid" ] ||
      [ "$hma_old_start" != "$hma_lock_start" ] || return 1
  fi
  rm -f "$hma_lock_path/boot" || return 1
  rmdir "$hma_lock_path" 2>/dev/null || return 1
  mkdir "$hma_lock_path" 2>/dev/null || return 1
  printf '%s %s %s\n' "$hma_lock_boot" "$hma_lock_pid" "$hma_lock_start" > "$hma_lock_path/boot" || return 1
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


# Single long-lived lightweight service watcher, with a stale-owner check.
// A framework soft reboot keeps the kernel ID but replaces system_server.
hma_monitor_lock() {
  hma_watch_path="$1" hma_watch_boot="$2"
  hma_watch_start=$(hma_process_start "$$")
  [ -n "$hma_watch_start" ] || return 1
  if mkdir "$hma_watch_path" 2>/dev/null; then
    printf '%s %s %s\n' "$hma_watch_boot" "$$" "$hma_watch_start" > "$hma_watch_path/owner" || return 1
    return 0
  fi
  [ -r "$hma_watch_path/owner" ] || return 1
  hma_owner_boot='' hma_owner_pid='' hma_owner_start=''
  IFS=' ' read -r hma_owner_boot hma_owner_pid hma_owner_start < "$hma_watch_path/owner" || return 1
  if [ "$hma_owner_boot" = "$hma_watch_boot" ] && [ -n "$hma_owner_pid" ] &&
     [ -n "$hma_owner_start" ] &&
     [ "$(hma_process_start "$hma_owner_pid")" = "$hma_owner_start" ] &&
     kill -0 "$hma_owner_pid" 2>/dev/null; then
    return 1
  fi
  rm -f "$hma_watch_path/owner" || return 1
  rmdir "$hma_watch_path" 2>/dev/null || return 1
  mkdir "$hma_watch_path" 2>/dev/null || return 1
  printf '%s %s %s\n' "$hma_watch_boot" "$$" "$hma_watch_start" > "$hma_watch_path/owner" || return 1
}

hma_monitor_release() {
  rm -f "$1/owner"
  rmdir "$1" 2>/dev/null || true
}

# At most two *unverified* native attempts per five-minute window in the
# same kernel boot. A verified handshake clears the budget. This prevents
# repeated framework crashes from turning a watchdog into a boot loop.
hma_record_native_attempt() {
  hma_budget_file="$1" hma_budget_boot="$2"
  hma_budget_now=$(date +%s) || return 1
  hma_budget_prev_boot='' hma_budget_prev_time='' hma_budget_count=''
  if [ -r "$hma_budget_file" ]; then
    IFS=' ' read -r hma_budget_prev_boot hma_budget_prev_time hma_budget_count < "$hma_budget_file" || return 1
  fi
  case "$hma_budget_prev_time:$hma_budget_count" in
    *[!0-9:]*|:*|*:) hma_budget_count=0; hma_budget_prev_time="$hma_budget_now" ;;
  esac
  if [ "$hma_budget_prev_boot" != "$hma_budget_boot" ] ||
     [ "$hma_budget_now" -lt "$hma_budget_prev_time" ] ||
     [ "$((hma_budget_now - hma_budget_prev_time))" -ge 300 ]; then
    hma_budget_count=0
    hma_budget_prev_time="$hma_budget_now"
  fi
  [ "$hma_budget_count" -lt 2 ] || return 1
  hma_budget_count=$((hma_budget_count + 1))
  printf '%s %s %s\n' "$hma_budget_boot" "$hma_budget_prev_time" "$hma_budget_count" > "$hma_budget_file" || return 1
}
