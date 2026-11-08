#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="${1:-$ROOT/app/build/outputs/apk/debug/HMA-OSS-debug.apk}"
NATIVE="${2:-$ROOT/sukisu/native/build}"
OUT="${3:-$ROOT/sukisu/build/HMA-OSS-SukiSU-experimental.zip}"
[[ -f "$APK" ]] || { echo "Missing APK: $APK" >&2; exit 1; }
[[ -f "$NATIVE/hma-injector" ]] || { echo 'Missing native injector' >&2; exit 1; }
[[ -f "$NATIVE/libhma-payload.so" ]] || { echo 'Missing native payload' >&2; exit 1; }
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
