#!/usr/bin/env bash
# Creates a local, self-signed code signing identity so macOS keeps camera and
# Accessibility grants across rebuilds. The certificate is not trusted for
# distribution; it only gives the app a stable signing identity on this Mac.
set -euo pipefail

NAME="Barcode Scanner Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
PASSWORD="barcode-scanner-local"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "Identity already exists: $NAME"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
openssl pkcs12 -export -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout "pass:$PASSWORD" 2>/dev/null

security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "Created local signing identity: $NAME"
