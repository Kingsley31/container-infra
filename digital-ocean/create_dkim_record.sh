#!/bin/bash
# Create DKIM DNS record on DigitalOcean
# Usage: ./create_dkim_record.sh <domain> <ip> <record_name> <record_value>
# Example: ./create_dkim_record.sh example.com 203.0.113.45 mail._domainkey "v=DKIM1; k=rsa; p=MIIBIjANBg..."

set -euo pipefail

DOMAIN="${1:-}"
IP="${2:-}"
RECORD_NAME="${3:-}"
RECORD_VALUE="${4:-}"

if [[ -z "$DOMAIN" || -z "$IP" || -z "$RECORD_NAME" || -z "$RECORD_VALUE" ]]; then
  echo "Usage: $0 <domain> <ip> <record_name> <record_value>"
  exit 1
fi

if [ -z "${DO_API_TOKEN:-}" ]; then
  echo "❌ DO_API_TOKEN environment variable is not set"
  exit 1
fi

API="https://api.digitalocean.com/v2"

echo "🌐 Creating DKIM TXT record for $DOMAIN..."
BODY=$(jq -nc \
  --arg type "TXT" \
  --arg name "$RECORD_NAME" \
  --arg data "$RECORD_VALUE" \
  '{type:$type, name:$name, data:$data}')

RESPONSE=$(curl -s -X POST "$API/domains/$DOMAIN/records" \
  -H "Authorization: Bearer $DO_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")

if echo "$RESPONSE" | jq -e '.domain_record.id' >/dev/null 2>&1; then
  echo "✅ DKIM record created successfully:"
  echo "$RECORD_NAME.$DOMAIN → $RECORD_VALUE"
else
  echo "❌ Failed to create DKIM record"
  echo "Response: $RESPONSE"
  exit 1
fi
