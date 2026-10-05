#!/usr/bin/env bash
# Create a local root CA and a server certificate signed by it (Mac 2, Task E).
# Run from this certs/ directory. Uses Homebrew OpenSSL 3 (macOS ships LibreSSL).
#
# Outputs: rootCA.key rootCA.pem  server.key server.csr server.crt
# Only rootCA.pem is shared with clients. *.key files are git-ignored — never commit them.
set -euo pipefail

OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
"$OPENSSL" version   # expect OpenSSL 3.x

# Root CA
"$OPENSSL" req -x509 -new -nodes -newkey rsa:2048 \
  -keyout rootCA.key -out rootCA.pem -days 825 \
  -config ca.cnf -extensions v3_ca

# Server key + CSR, signed by the CA
"$OPENSSL" req -new -nodes -newkey rsa:2048 \
  -keyout server.key -out server.csr -config leaf.cnf
"$OPENSSL" x509 -req -in server.csr -CA rootCA.pem -CAkey rootCA.key \
  -CAcreateserial -out server.crt -days 397 -sha256 \
  -extfile leaf.cnf -extensions v3_leaf

# Verify
"$OPENSSL" verify -CAfile rootCA.pem server.crt
"$OPENSSL" x509 -in server.crt -noout -ext subjectAltName
