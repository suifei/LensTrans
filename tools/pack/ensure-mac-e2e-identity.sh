#!/usr/bin/env bash
# Create or reuse a stable local-only code-signing identity for Screen Recording TCC.
# The private key lives in the user's login keychain; no key material enters the repo.
set -euo pipefail

NAME="LensTrans Local E2E Code Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$NAME\""; then
  echo "$NAME"
  exit 0
fi

KEYCHAIN=$(security default-keychain -d user \
  | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/')
if [[ -z "$KEYCHAIN" ]]; then
  echo "Unable to resolve the user login keychain." >&2
  exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lenstrans-codesign.XXXXXX")
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -subj "/CN=$NAME/O=LensTrans Local Development" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
PASS=$(openssl rand -hex 24)
openssl pkcs12 -export -name "$NAME" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
  -out "$TMP/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1
security import "$TMP/identity.p12" -k "$KEYCHAIN" -f pkcs12 \
  -P "$PASS" -T /usr/bin/codesign >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" \
  "$TMP/cert.pem" >/dev/null

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$NAME\""; then
  echo "Imported $NAME, but Keychain does not consider it a valid signing identity." >&2
  exit 3
fi
echo "$NAME"
