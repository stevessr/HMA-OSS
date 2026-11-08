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
    [ "$local_start" = "$4" ]
}

hma_workmode_ok() {
  [ -r "$1" ] &&
    grep -Eq '"workMode"[[:space:]]*:[[:space:]]*1([^0-9]|$)' "$1"
}

hma_fresh_workmode_ok() {
  [ -r "$1" ] || return 1
  file_time=$(stat -c %Y "$1" 2>/dev/null) || return 1
  case "$file_time" in ''|*[!0-9]*) return 1 ;; esac
  [ "$file_time" -gt "$2" ] && hma_workmode_ok "$1"
}
