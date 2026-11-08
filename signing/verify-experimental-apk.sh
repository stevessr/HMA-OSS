#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="${1:?usage: verify-experimental-apk.sh <APK>}"
bash "$ROOT/signing/verify-experimental-keystore.sh"
: "${ANDROID_HOME:?ANDROID_HOME must point to Android SDK to find apksigner}"
APKSIGNER="$(find "$ANDROID_HOME/build-tools" -maxdepth 2 -type f -name apksigner | sort -V | tail -1)"
test -x "$APKSIGNER" || { echo 'Android SDK apksigner not installed' >&2; exit 1; }
expected="$(tr -d '[:space:]:' < "$ROOT/signing/EXPERIMENTAL_CERT_SHA256.txt" | tr '[:lower:]' '[:upper:]')"
details="$("$APKSIGNER" verify --verbose --print-certs "$APK")"
actual="$(printf '%s\n' "$details" |
  sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 |
  tr -d '[:space:]:' | tr '[:lower:]' '[:upper:]')"
[[ -n "$actual" && "$actual" == "$expected" ]] || {
  echo 'APK certificate differs from the checked-in experimental test key' >&2
  echo "Expected: $expected" >&2
  echo "Found: $actual" >&2
  exit 1
}
echo "APK certificate verified: $actual"
