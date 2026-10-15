#!/usr/bin/env bash
# Creates a self-signed code-signing certificate for Marquee releases and prints the
# three values to save as GitHub Actions secrets. Run it once, on your Mac.
#
#   ./scripts/create-signing-cert.sh ["Certificate Name"]
#
# Why: macOS remembers Screen Recording and Accessibility permissions per signing
# identity. Ad-hoc builds get a new identity every release, so users are asked again
# after each update. Signing every release with this one certificate avoids that.
set -euo pipefail

NAME="${1:-Marquee Code Signing}"
OUT="marquee-signing.p12"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -e "$OUT" ]]; then
  echo "$OUT already exists. Move it away first so it isn't overwritten." >&2
  exit 1
fi

PASSWORD="$(openssl rand -base64 24)"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null

# OpenSSL 3 needs -legacy so the macOS keychain can import the file; LibreSSL doesn't have it.
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$OUT" -passout "pass:$PASSWORD"

cat <<EOF

Created $OUT. Keep it private and don't commit it.

Add these three secrets in GitHub → Settings → Secrets and variables → Actions:

  MACOS_SIGNING_IDENTITY       $NAME
  MACOS_SIGNING_CERT_PASSWORD  $PASSWORD
  MACOS_SIGNING_CERT_P12       (the base64 text below)

$(base64 < "$OUT")

To sign local builds with the same identity, double-click $OUT to import it into your
login keychain, then run:  SIGN_IDENTITY="$NAME" make app
EOF
