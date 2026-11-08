#!/system/bin/sh
# Shared fail-closed state checks. This file only defines functions.
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
    [ "$local_start" = "$4"
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
