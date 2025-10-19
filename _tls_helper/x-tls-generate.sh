#!/usr/bin/env bash
set -euo pipefail

# Simple TLS helper: creates a local CA (10 years) and a server cert for a hostname.
# Re-entrant: remembers the last hostname in _tls_helper.state and only (re)creates what is needed.
# All generated artifacts live in ./certs relative to this script's directory.
# If a different hostname is requested than the previous one, removes old server certs and recreates them.
# Keeps the CA if still valid (not expired).

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="$THIS_DIR/certs"
STATE_FILE="$THIS_DIR/_tls_helper.state"

# OpenSSL binaries
OPENSSL_BIN=${OPENSSL_BIN:-openssl}

mkdir -p "$CERTS_DIR"

# Load previous state if any
PREV_HOSTNAME=""
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
  PREV_HOSTNAME=${HOSTNAME:-}
fi

# Read hostname from args or prompt
REQ_HOSTNAME="${1:-}"
if [[ -z "$REQ_HOSTNAME" ]]; then
  DEFAULT_HINT=""
  if [[ -n "$PREV_HOSTNAME" ]]; then
    DEFAULT_HINT="[$PREV_HOSTNAME] "
  fi
  read -r -p "Enter certificate hostname ${DEFAULT_HINT}" REQ_HOSTNAME || true
  if [[ -z "$REQ_HOSTNAME" && -n "$PREV_HOSTNAME" ]]; then
    REQ_HOSTNAME="$PREV_HOSTNAME"
  fi
fi

# Basic validation
if [[ -z "$REQ_HOSTNAME" ]]; then
  echo "Error: hostname must not be empty." >&2
  exit 1
fi

# Persist state if changed
if [[ "$REQ_HOSTNAME" != "$PREV_HOSTNAME" ]]; then
  echo "HOSTNAME='$REQ_HOSTNAME'" > "$STATE_FILE"
fi

# Determine if CA exists and is valid
CA_KEY="$CERTS_DIR/ca.key.pem"
CA_CRT="$CERTS_DIR/ca.crt.pem"

ca_valid=false
if [[ -f "$CA_KEY" && -f "$CA_CRT" ]]; then
  if $OPENSSL_BIN x509 -in "$CA_CRT" -noout -checkend 0 >/dev/null 2>&1; then
    ca_valid=true
  fi
fi

# Create CA if missing or expired
if [[ "$ca_valid" != true ]]; then
  echo "[TLS] Creating local CA (10 years)"
  $OPENSSL_BIN genrsa -out "$CA_KEY" 4096 >/dev/null 2>&1
  $OPENSSL_BIN req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
    -subj "/C=US/O=Local Dev/CN=Local Dev Root CA" -out "$CA_CRT" >/dev/null 2>&1
  ca_valid=true
fi

# Determine current server cert files (fixed names, no symlinks)
SERVER_KEY="$CERTS_DIR/server.key.pem"
SERVER_CSR="$CERTS_DIR/server.csr.pem"
SERVER_CRT="$CERTS_DIR/server.crt.pem"
SERVER_CHAIN="$CERTS_DIR/server.fullchain.pem"

# If hostname changed from previous run, remove old server artifacts (keep CA if valid)
if [[ -n "$PREV_HOSTNAME" && "$REQ_HOSTNAME" != "$PREV_HOSTNAME" ]]; then
  echo "[TLS] Hostname changed ($PREV_HOSTNAME -> $REQ_HOSTNAME). Cleaning old server certs."
  rm -f "$SERVER_KEY" \
        "$SERVER_CSR" \
        "$SERVER_CRT" \
        "$SERVER_CHAIN"
fi

# Helper: check if an existing server cert matches the hostname and is valid
server_cert_ok=false
if [[ -f "$SERVER_CRT" ]]; then
  if $OPENSSL_BIN x509 -in "$SERVER_CRT" -noout -checkend 0 >/dev/null 2>&1; then
    # Verify SAN contains hostname
    if $OPENSSL_BIN x509 -in "$SERVER_CRT" -noout -text | grep -q "Subject Alternative Name"; then
      if $OPENSSL_BIN x509 -in "$SERVER_CRT" -noout -text | grep -E "DNS:$REQ_HOSTNAME(,|$)" >/dev/null 2>&1; then
        server_cert_ok=true
      fi
    else
      # Fallback to CN if SAN missing
      if $OPENSSL_BIN x509 -in "$SERVER_CRT" -noout -subject | grep -q "CN=$REQ_HOSTNAME"; then
        server_cert_ok=true
      fi
    fi
  fi
fi

# If server cert not ok, (re)create
if [[ "$server_cert_ok" != true ]]; then
  echo "[TLS] Creating server certificate for $REQ_HOSTNAME (10 years)"
  # Generate private key
  if [[ ! -f "$SERVER_KEY" ]]; then
    $OPENSSL_BIN genrsa -out "$SERVER_KEY" 2048 >/dev/null 2>&1
  fi

  # Build a minimal openssl config with SANs
  SAN_LOCAL="DNS:localhost,IP:127.0.0.1"
  SAN_HOST="DNS:$REQ_HOSTNAME"
  EXT_FILE=$(mktemp)
  cat > "$EXT_FILE" <<EOF
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $SAN_HOST,$SAN_LOCAL
EOF

  # Create CSR
  $OPENSSL_BIN req -new -key "$SERVER_KEY" -subj "/C=US/O=Local Dev/CN=$REQ_HOSTNAME" -out "$SERVER_CSR" >/dev/null 2>&1

  # Sign with CA
  $OPENSSL_BIN x509 -req -in "$SERVER_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$SERVER_CRT" -days 3650 -sha256 -extfile "$EXT_FILE" >/dev/null 2>&1 || {
      rm -f "$EXT_FILE"
      echo "[TLS] Error: failed to sign server cert" >&2
      exit 1
    }
  rm -f "$EXT_FILE" "$CERTS_DIR/ca.srl" 2>/dev/null || true

  # Create full chain
  cat "$SERVER_CRT" "$CA_CRT" > "$SERVER_CHAIN"
fi

# No symlinks are created; files use fixed names.

# Generate/validate Diffie-Hellman parameters (4096-bit)
DH_PARAM="$CERTS_DIR/dhparam.pem"
dh_ok=false
if [[ -f "$DH_PARAM" ]]; then
  if $OPENSSL_BIN dhparam -in "$DH_PARAM" -text -noout 2>/dev/null | grep -q "4096 bit"; then
    dh_ok=true
  fi
fi
if [[ "$dh_ok" != true ]]; then
  echo "[TLS] Generating Diffie-Hellman parameters (4096-bit). This may take a while..."
  $OPENSSL_BIN dhparam -out "$DH_PARAM" 4096 >/dev/null 2>&1
fi

# Final output
cat <<MSG

[TLS] Done.
- CA cert:       $CA_CRT
- Server key:    $SERVER_KEY
- Server cert:   $SERVER_CRT
- Full chain:    $SERVER_CHAIN
- DH params:     $DH_PARAM
- State file:    $STATE_FILE

Tip: You can run this script again; it will only recreate items if needed.
You may also pass the hostname as the first argument to skip the prompt, e.g.:
  $0 example.local
MSG
