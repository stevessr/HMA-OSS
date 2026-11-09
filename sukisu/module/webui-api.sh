#!/system/bin/sh
# Narrow, fixed subcommands for KernelSU's root WebUI bridge. No user-supplied
# package names, file paths, shell snippets or destructive uninstall commands.
MODDIR="${0%/*}"
. "$MODDIR/state.sh" || exit 1
. "$MODDIR/manager-apk.sh" || exit 1

case "${1:-status}" in
  status)
    echo "version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" | head -n 1)"
    if [ -s "$MODDIR/manager.apk" ]; then echo 'bundled=yes'; else echo 'bundled=no'; fi
    if hma_manager_installed_apk >/dev/null; then
      echo 'installed=yes'
    else
      echo 'installed=no'
    fi
    if [ -f "$MODDIR/disable" ]; then echo 'module=disabled'; else echo 'module=enabled'; fi
    if [ -f "$MODDIR/enabled" ]; then echo 'autostart=enabled'; else echo 'autostart=disabled'; fi
    boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    server_pid=$(pidof system_server 2>/dev/null | awk '{print $1}')
    server_start=$(hma_system_server_start)
    echo "server_pid=${server_pid:-unknown}"
    if hma_install_reboot_pending "$MODDIR/installed_boot_id" "$boot_id" "$server_start"; then
      echo 'reboot=pending'
    else
      echo 'reboot=ready'
    fi
    if hma_install_reboot_pending "$MODDIR/injection_failed" "$boot_id" "$server_start"; then
      echo 'injection=failed_this_system_server'
    elif hma_pid_marker_matches "$MODDIR/injected_pid" "$boot_id" "$server_pid" "$server_start"; then
      echo 'injection=verified'
    else
      echo 'injection=not_verified'
    fi
    ;;
  install)
    hma_manager_install
    ;;
  start)
    if [ -f "$MODDIR/enabled" ]; then
      # A soft reboot can leave autostart enabled without this new process
      # having an injected backend. Verify/recover rather than saying done.
      sh "$MODDIR/try-inject.sh"
    else
      sh "$MODDIR/action.sh"
    fi
    ;;
  stop)
    if [ -f "$MODDIR/enabled" ]; then
      sh "$MODDIR/action.sh"
    else
      echo 'Next-boot autostart is already disabled.'
    fi
    ;;
  logs)
    if [ -f "$MODDIR/log/service.log" ]; then
      tail -n 120 "$MODDIR/log/service.log"
    else
      echo 'No service.log yet. Start a test injection to generate diagnostics.'
    fi
    ;;
  *)
    echo 'Unsupported WebUI operation' >&2
    exit 2
    ;;
esac
