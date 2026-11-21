#!/bin/bash
set -euo pipefail
umask 077

identity="Book Brain Local Development"
if security find-identity -v -p codesigning | grep -Fq -- "\"$identity\""; then
  printf 'Signing identity already exists: %s\n' "$identity"
  exit 0
fi
if security find-certificate -c "$identity" >/dev/null 2>&1; then
  printf 'A certificate named %s already exists but is not a valid signing identity. Repair it in Keychain Access rather than replacing it and losing existing app permissions.\n' "$identity" >&2
  exit 1
fi

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
keychain="$(security default-keychain -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')"
/usr/bin/openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
  -subj "/CN=$identity/" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,digitalSignature,keyCertSign' \
  -addext 'extendedKeyUsage=critical,codeSigning' \
  -keyout "$temporary/key.pem" -out "$temporary/certificate.pem" 2>/dev/null
printf 'Creating %s in your login keychain. macOS may ask you to approve code-signing trust.\n' "$identity"
security import "$temporary/key.pem" -k "$keychain" -x -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temporary/certificate.pem"
security find-identity -v -p codesigning | grep -F -- "\"$identity\""
printf 'Local code-signing identity is ready. Keep it across builds to preserve app permissions.\n'
