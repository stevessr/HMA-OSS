#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="${1:-$ROOT/app/build/outputs/apk/debug/HMA-OSS-debug.apk}"
NATIVE="${2:-$ROOT/sukisu/native/build}"
OUT="${3:-$ROOT/sukisu/build/HMA-OSS-SukiSU-experimental.zip}"
[[ -f "$APK" ]] || { echo "Missing APK: $APK" >&2; exit 1; }
[[ -f "$NATIVE/hma-injector" ]] || { echo 'Missing native injector' >&2; exit 1; }
[[ -f "$NATIVE/libhma-payload.so" ]] || { echo 'Missing native payload' >&2; exit 1; }
# Do not turn an unrelated archive or wrong-architecture executable into a
# privileged root module, even when package.sh is called outside Actions.
unzip -tqq "$APK" >/dev/null || { echo 'APK is not a valid ZIP' >&2; exit 1; }
for required in AndroidManifest.xml classes.dex; do
  unzip -Z1 "$APK" | grep -Fx "$required" >/dev/null ||
    { echo "APK missing $required" >&2; exit 1; }
done
if command -v llvm-readelf >/dev/null 2>&1; then
  ELF_TOOL=llvm-readelf
elif command -v readelf >/dev/null 2>&1; then
  ELF_TOOL=readelf
else
  echo 'Packaging requires readelf or llvm-readelf for ABI verification' >&2
  exit 1
fi
for binary in "$NATIVE/hma-injector" "$NATIVE/libhma-payload.so"; do
  "$ELF_TOOL" -h "$binary" | grep -F 'AArch64' >/dev/null ||
    { echo "Expected arm64 ELF binary: $binary" >&2; exit 1; }
done
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/sukisu/module/"* "$STAGE/"
mkdir -p "$STAGE/bin" "$STAGE/lib"
cp "$NATIVE/hma-injector" "$STAGE/bin/hma-injector"
cp "$NATIVE/libhma-payload.so" "$STAGE/lib/libhma-payload.so"
cp "$APK" "$STAGE/manager.apk"
chmod 0755 "$STAGE"/*.sh "$STAGE/bin/hma-injector"
mkdir -p "$(dirname "$OUT")"
OUT="$(realpath -m "$OUT")"
(cd "$STAGE" && zip -qr "$OUT" .)
echo "$OUT"
