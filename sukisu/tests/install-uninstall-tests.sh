#!/usr/bin/env bash
# Exercise the real installer and uninstaller without touching /data/adb.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ADB="$TMP/adb"
MOD="$TMP/module"
mkdir -p "$MOD/bin" "$MOD/lib" "$ADB/modules/hma_oss_zygisk"
mkdir -p "$ADB/boot-completed.d" "$TMP/config/hide_my_applist_keep"
printf 'id=hma_sukisu\n' > "$MOD/module.prop"
printf 'id=hma_oss_zygisk\n' > "$ADB/modules/hma_oss_zygisk/module.prop"
printf 'kept-config\n' > "$TMP/config/hide_my_applist_keep/config.json"
printf 'MODDIR=/data/adb/modules/hma_oss_zygisk\ncp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"\n' > "$ADB/boot-completed.d/hmaoss.sh"
touch "$MOD/bin/hma-injector" "$MOD/lib/libhma-payload.so" "$MOD/manager.apk"
cp "$ROOT/sukisu/module/legacy-cleanup.sh" "$MOD/"

# Rewrite only the fixed /data/adb fixture root in a disposable script copy.
sed "s@hma_legacy_migrate /data/adb@hma_legacy_migrate $ADB@" \
  "$ROOT/sukisu/module/customize.sh" > "$MOD/customize-test.sh"
grep -Fq "hma_legacy_migrate $ADB" "$MOD/customize-test.sh"
cat > "$TMP/install-runner.sh" <<'EOF'
#!/bin/sh
ui_print() { echo "$1"; }
abort() { echo "$1" >&2; exit 91; }
set_perm() { :; }
getprop() {
  case "$1" in
    ro.product.cpu.abi) echo arm64-v8a ;;
    ro.build.version.sdk) echo 35 ;;
    *) exit 1 ;;
  esac
}
. "$1"
EOF
KSU=true MODPATH="$MOD" sh "$TMP/install-runner.sh" "$MOD/customize-test.sh"
[ -f "$ADB/modules/hma_oss_zygisk/remove" ]
[ -f "$ADB/modules/hma_oss_zygisk/disable" ]
[ ! -f "$ADB/boot-completed.d/hmaoss.sh" ]
[ -s "$MOD/installed_boot_id" ]
[ ! -f "$MOD/enabled" ]
[ "$(cat "$TMP/config/hide_my_applist_keep/config.json")" = kept-config ]

# The actual uninstaller must clean its own markers and a future stale hook,
# while leaving the HMA configuration and unrelated root scripts untouched.
mkdir -p "$ADB/boot-completed.d"
printf 'MODDIR=/data/adb/modules/hma_oss_zygisk\ncp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"\n' > "$ADB/boot-completed.d/hmaoss.sh"
mkdir -p "$ADB/post-fs-data.d"
printf '# foreign owner\n' > "$ADB/post-fs-data.d/hmaoss.sh"
touch "$MOD/enabled" "$MOD/injected_pid" "$MOD/injection_failed"
mkdir "$MOD/.inject-lock"
printf 'old-boot\n' > "$MOD/.inject-lock/boot"
sed "s@hma_legacy_cleanup_scripts /data/adb@hma_legacy_cleanup_scripts $ADB@" \
  "$ROOT/sukisu/module/uninstall.sh" > "$MOD/uninstall-test.sh"
grep -Fq "hma_legacy_cleanup_scripts $ADB" "$MOD/uninstall-test.sh"
sh "$MOD/uninstall-test.sh"
for f in installed_boot_id enabled injected_pid injection_failed; do
  [ ! -e "$MOD/$f" ]
done
[ ! -d "$MOD/.inject-lock" ]
[ ! -f "$ADB/boot-completed.d/hmaoss.sh" ]
[ -f "$ADB/post-fs-data.d/hmaoss.sh" ]
[ "$(cat "$TMP/config/hide_my_applist_keep/config.json")" = kept-config ]
echo 'SukiSU mocked installation and uninstall preservation tests passed'
