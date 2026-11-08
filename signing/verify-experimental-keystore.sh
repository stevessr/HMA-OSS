#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/signing/hma-oss-experimental.p12"
expected="$(tr -d '[:space:]:' < "$ROOT/signing/EXPERIMENTAL_CERT_SHA256.txt" | tr '[:lower:]' '[:upper:]')"
test -s "$FILE"
actual="$(keytool -list -v -keystore "$FILE" -storetype PKCS12 -storepass hma-experimental-public -alias hma-experimental |
  sed -n 's/^[[:space:]]*SHA256: //p' | head -1 | tr -d '[:space:]:' | tr '[:lower:]' '[:upper:]')"
if [[ -z "$actual" || "$actual" != "$expected" ]]; then
  echo 'Public experimental keystore certificate does not match pinned fingerprint' >&2
  exit 1
fi
echo "Experimental keystore certificate SHA-256: $actual"
