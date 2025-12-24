#!/bin/bash
# =============================================================================
# Generate mTLS Certificates for Cloudflare Authenticated Origin Pulls
# =============================================================================
#
# This script generates a custom CA certificate and client certificate
# for mTLS between Cloudflare and the origin server.
#
# Using a custom certificate (not Cloudflare's shared cert) prevents
# other Cloudflare users from pointing their domains at our origin.
#
# Usage:
#   ./generate-mtls-certs.sh [output_dir]
#
# Output:
#   - ca.key         - CA private key (keep secret!)
#   - ca.crt         - CA certificate (configure on origin server)
#   - client.key     - Client private key
#   - client.crt     - Client certificate
#   - client.pem     - Combined client cert + key (upload to Cloudflare)

set -euo pipefail

OUTPUT_DIR="${1:-./certs}"
mkdir -p "$OUTPUT_DIR"

echo "=== Generating mTLS Certificates ==="
echo "Output directory: $OUTPUT_DIR"
echo

# -----------------------------------------------------------------------------
# Generate CA Certificate
# -----------------------------------------------------------------------------

echo "1. Generating CA private key..."
openssl genrsa -out "$OUTPUT_DIR/ca.key" 4096

echo "2. Generating CA certificate (10 year validity)..."
openssl req -new -x509 -days 3650 -key "$OUTPUT_DIR/ca.key" \
  -subj "/CN=Plue Origin CA/O=Plue/C=US" \
  -out "$OUTPUT_DIR/ca.crt"

# -----------------------------------------------------------------------------
# Generate Client Certificate
# -----------------------------------------------------------------------------

echo "3. Generating client private key..."
openssl genrsa -out "$OUTPUT_DIR/client.key" 4096

echo "4. Generating client CSR..."
openssl req -new -key "$OUTPUT_DIR/client.key" \
  -subj "/CN=Cloudflare Client/O=Plue/C=US" \
  -out "$OUTPUT_DIR/client.csr"

echo "5. Signing client certificate with CA (1 year validity)..."
openssl x509 -req -days 365 -in "$OUTPUT_DIR/client.csr" \
  -CA "$OUTPUT_DIR/ca.crt" -CAkey "$OUTPUT_DIR/ca.key" \
  -CAcreateserial -out "$OUTPUT_DIR/client.crt"

# Combine client cert and key for Cloudflare upload
echo "6. Creating combined client PEM..."
cat "$OUTPUT_DIR/client.crt" "$OUTPUT_DIR/client.key" > "$OUTPUT_DIR/client.pem"

# Clean up CSR
rm -f "$OUTPUT_DIR/client.csr"

# -----------------------------------------------------------------------------
# Set Permissions
# -----------------------------------------------------------------------------

echo "7. Setting secure permissions..."
chmod 600 "$OUTPUT_DIR/ca.key"
chmod 600 "$OUTPUT_DIR/client.key"
chmod 600 "$OUTPUT_DIR/client.pem"
chmod 644 "$OUTPUT_DIR/ca.crt"
chmod 644 "$OUTPUT_DIR/client.crt"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Extract Certificate Info
# -----------------------------------------------------------------------------

echo "8. Extracting certificate information..."

# Get client certificate expiry date
CLIENT_EXPIRY=$(openssl x509 -in "$OUTPUT_DIR/client.crt" -noout -enddate | cut -d= -f2)
CLIENT_EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$CLIENT_EXPIRY" +%s 2>/dev/null || \
                      date -d "$CLIENT_EXPIRY" +%s 2>/dev/null)
CLIENT_EXPIRY_DAYS=$(( (CLIENT_EXPIRY_EPOCH - $(date +%s)) / 86400 ))

# Get CA certificate expiry date
CA_EXPIRY=$(openssl x509 -in "$OUTPUT_DIR/ca.crt" -noout -enddate | cut -d= -f2)

# Save expiry info to file for reference
cat > "$OUTPUT_DIR/expiry-info.json" << EOF
{
  "client_cert_expiry": "$CLIENT_EXPIRY",
  "client_cert_expiry_epoch": $CLIENT_EXPIRY_EPOCH,
  "client_cert_expiry_days": $CLIENT_EXPIRY_DAYS,
  "ca_cert_expiry": "$CA_EXPIRY",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo
echo "=== Certificates Generated Successfully ==="
echo
echo "Files created:"
ls -la "$OUTPUT_DIR"
echo
echo "Certificate Expiry:"
echo "  Client certificate expires: $CLIENT_EXPIRY ($CLIENT_EXPIRY_DAYS days from now)"
echo "  CA certificate expires:     $CA_EXPIRY"
echo
echo "Next steps:"
echo "  1. Upload client.pem to Cloudflare for Authenticated Origin Pulls"
echo "  2. Configure origin server with ca.crt to verify client certificates"
echo "  3. Store ca.key securely - needed to renew client certificate"
echo "  4. Set up calendar reminder to rotate before: $CLIENT_EXPIRY"
echo
echo "To store in Terraform:"
echo "  export TF_VAR_mtls_client_cert=\$(cat $OUTPUT_DIR/client.crt)"
echo "  export TF_VAR_mtls_client_key=\$(cat $OUTPUT_DIR/client.key)"
echo "  export TF_VAR_mtls_ca_cert=\$(cat $OUTPUT_DIR/ca.crt)"
echo
echo "To push cert expiry as Prometheus metric (run on API server):"
echo "  curl -s -XPOST 'http://localhost:4000/metrics/push' \\"
echo "    -d 'plue_mtls_cert_expiry_seconds{cert=\"client\"} $CLIENT_EXPIRY_EPOCH'"
echo
