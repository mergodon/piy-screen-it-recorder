#!/usr/bin/env zsh
# Create a self-signed code-signing identity in the login keychain, once per Mac.
# build.sh uses it when SIGN_ID is unset. A stable signature means macOS keeps the
# Screen Recording / Camera / Microphone permission across rebuilds; ad-hoc signing
# makes every build a new app. Use a real Developer ID (SIGN_ID) for builds you share.
set -euo pipefail

NAME="ScreenItRecorder Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Already exists: $NAME"; exit 0
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=$(openssl rand -hex 16)
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
  -out "$tmp/id.p12" -passout "pass:$pass" 2>/dev/null || \
openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
  -out "$tmp/id.p12" -passout "pass:$pass" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import "$tmp/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign
echo "Created: $NAME"
