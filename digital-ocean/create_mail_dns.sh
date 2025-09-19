#!/bin/bash
# Create mail DNS records on DigitalOcean via API
# Usage: ./create_mail_dns.sh <domain> <droplet_public_ip>
# Example: ./create_mail_dns.sh example.com 203.0.113.45

set -euo pipefail

# --- Usage check ---
if [[ $# -lt 2 ]]; then
  echo "❌ Missing arguments."
  echo "Usage: $0 <domain> <droplet_public_ip>"
  echo "Example: $0 example.com 203.0.113.45"
  exit 1
fi

DOMAIN="$1"
IP="$2"

if [ -z "${DO_API_TOKEN:-}" ]; then
  echo "❌ DO_API_TOKEN environment variable is not set"
  exit 1
fi

API="https://api.digitalocean.com/v2"

# Helper: create DNS record
create_record() {
  local type="$1"
  local name="$2"
  local data="$3"
  local priority="${4:-}"

  body="{\"type\":\"$type\",\"name\":\"$name\",\"data\":\"$data\""
  if [[ -n "$priority" ]]; then
    body+=",\"priority\":$priority"
  fi
  body+="}"

  echo "Creating $type record: $name → $data"
  RESPONSE=$(curl -s -X POST "$API/domains/$DOMAIN/records" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$body")

  if echo "$RESPONSE" | jq -e '.domain_record.id' >/dev/null 2>&1; then
    echo "✅ $type record created successfully"
  else
    echo "❌ Failed to create $type record"
    echo "Response: $RESPONSE"
    exit 1
  fi
}

# 1. A record for mail.<domain> pointing to the Droplet IP
create_record A "mail" "$IP"

# 2. MX record for the root domain pointing to mail.<domain>
create_record MX "@" "mail.${DOMAIN}." 10

# 3. SPF TXT record for the root domain
create_record TXT "@" "v=spf1 mx -all"

# 4. DMARC TXT record
create_record TXT "_dmarc" "v=DMARC1; p=quarantine; rua=mailto:admin@${DOMAIN}"

echo "🎉 All records created successfully."
