#!/usr/bin/env bash
set -euo pipefail

# x-tls-distribute-to-docker.sh
# Copies the generated TLS materials to the docker nginx service directory.
# Sources (produced by x-tls-generate.sh):
#   - _tls_helper/certs/server.crt.pem
#   - _tls_helper/certs/server.key.pem
#   - _tls_helper/certs/dhparam.pem
# Destination (mounted by docker-compose for nginx):
#   - ./docker-wrapper/nginx-service/certs/
#     with filenames unchanged.
#
# Usage:
#   bash _tls_helper/x-tls-distribute-to-docker.sh
#
# Notes:
# - This script does not regenerate TLS assets; it only copies.
#   Run _tls_helper/x-tls-generate.sh first if you haven’t created them yet.

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$THIS_DIR/.." && pwd)"
SRC_DIR="$THIS_DIR/certs"
DST_DIR="$ROOT_DIR/docker-wrapper/nginx-service/certs"

SRC_CERT="$SRC_DIR/server.crt.pem"
SRC_KEY="$SRC_DIR/server.key.pem"
SRC_DH="$SRC_DIR/dhparam.pem"

# Validate sources
missing=()
[[ -f "$SRC_CERT" ]] || missing+=("$SRC_CERT")
[[ -f "$SRC_KEY" ]] || missing+=("$SRC_KEY")
[[ -f "$SRC_DH" ]]   || missing+=("$SRC_DH")

if (( ${#missing[@]} > 0 )); then
  echo "[TLS] Error: Required source file(s) missing:" >&2
  for f in "${missing[@]}"; do
    echo "  - $f" >&2
  done
  echo "Hint: Run _tls_helper/x-tls-generate.sh to create the TLS materials." >&2
  exit 1
fi

# Ensure destination exists
mkdir -p "$DST_DIR"

# Copy files (overwrite)
cp -f "$SRC_CERT" "$DST_DIR/server.crt.pem"
cp -f "$SRC_KEY"  "$DST_DIR/server.key.pem"
cp -f "$SRC_DH"   "$DST_DIR/dhparam.pem"

# Restrict key permissions (best effort)
chmod 600 "$DST_DIR/server.key.pem" 2>/dev/null || true

cat <<MSG
[TLS] Distribution complete.
- From: $SRC_DIR
- To:   $DST_DIR

Installed files:
- $DST_DIR/server.crt.pem
- $DST_DIR/server.key.pem (mode may be tightened to 600)
- $DST_DIR/dhparam.pem

These files are used by docker-wrapper/nginx-service via docker-compose.
MSG
