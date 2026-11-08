#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/sukisu/module/legacy-cleanup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ADB="$TMP/adb"
mkdir -p "$ADB/modules/hma_oss_zygisk" "$ADB/modules_update/hma_oss_zygisk"
mkdir -p "$ADB/modules/another_module" "$ADB/boot-completed.d" "$ADB/post-fs-data.d" "$ADB/post-mount.d"
printf 'id=hma_oss_zygisk\n' > "$ADB/modules/hma_oss_zygisk/module.prop"
printf 'id=hma_oss_zygisk\n' > "$ADB/modules_update/hma_oss_zygisk/module.prop.bak"
printf 'id=another_module\n' > "$ADB/modules/another_module/module.prop"
printf 'MODDIR=/data/adb/modules/hma_oss_zygisk\ncp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"\n' > "$ADB/boot-completed.d/hmaoss.sh"
cp "$ADB/boot-completed.d/hmaoss.sh" "$ADB/post-mount.d/hmaoss.sh"
printf '# unrelated script\n' > "$ADB/post-fs-data.d/hmaoss.sh"
mkdir -p "$TMP/misc/hide_my_applist_example"
printf 'keep-me\n' > "$TMP/misc/hide_my_applist_example/config.json"
hma_legacy_migrate "$ADB"
[ "$HMA_LEGACY_FOUND" -eq 1 ]
for dir in "$ADB/modules/hma_oss_zygisk" "$ADB/modules_update/hma_oss_zygisk"; do
  [ -f "$dir/disable" ]
  [ -f "$dir/remove" ]
  [ -d "$dir" ]
done
[ ! -f "$ADB/boot-completed.d/hmaoss.sh" ]
[ ! -f "$ADB/post-mount.d/hmaoss.sh" ]
[ -f "$ADB/post-fs-data.d/hmaoss.sh" ]
[ -f "$ADB/modules/another_module/module.prop" ]
[ "$(cat "$TMP/misc/hide_my_applist_example/config.json")" = keep-me ]
# Idempotent reinstall does not recreate legacy scripts or touch config.
hma_legacy_migrate "$ADB"
[ "$HMA_LEGACY_FOUND" -eq 1 ]
# Legacy directory with an incorrect ID must be rejected instead of modified.
mkdir -p "$TMP/foreign/modules/hma_oss_zygisk"
printf 'id=not_hma\n' > "$TMP/foreign/modules/hma_oss_zygisk/module.prop"
if hma_legacy_migrate "$TMP/foreign"; then
  echo 'Wrong module identity was unexpectedly accepted' >&2
  exit 1
fi
[ ! -e "$TMP/foreign/modules/hma_oss_zygisk/remove" ]
# Never traverse a symlink masquerading as a module directory.
mkdir -p "$TMP/link/modules" "$TMP/target"
ln -s "$TMP/target" "$TMP/link/modules/hma_oss_zygisk"
if hma_legacy_migrate "$TMP/link"; then
  echo 'Symlinked module was unexpectedly accepted' >&2
  exit 1
fi
[ ! -e "$TMP/target/remove" ]
# Independent cleanup must remove only recognizable scripts.
# The first cleanup removes the now-empty directory as intended.
mkdir -p "$ADB/boot-completed.d"
printf '#!/system/bin/sh\nMODDIR=/data/adb/modules/hma_oss_zygisk\ncp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"\n' > "$ADB/boot-completed.d/hmaoss.sh"
hma_legacy_cleanup_scripts "$ADB"
[ ! -f "$ADB/boot-completed.d/hmaoss.sh" ]
echo 'Legacy migration, rollback safety and preservation tests passed'
