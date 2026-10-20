#!/usr/bin/env bash
# Creates a self-signed code-signing certificate, "Mousse Local", in your login keychain.
# build.sh signs with it automatically, so every build has the same identity and macOS keeps
# Mousse's Accessibility permission across rebuilds. It isn't trusted by anything and
# doesn't need to be: macOS only checks that each build is signed by the same key.
# Optional. Remove it any time in Keychain Access (login keychain → My Certificates).
set -euo pipefail

NAME="Mousse Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists."
  exit 0
fi

umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# macOS's own openssl (LibreSSL) writes a .p12 that `security import` can read;
# Homebrew's OpenSSL 3 uses a newer format it can't.
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -name "$NAME" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$PASS"

# -T lets codesign use the key without asking each time.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Created \"$NAME\". Run ./build.sh to sign with it."
