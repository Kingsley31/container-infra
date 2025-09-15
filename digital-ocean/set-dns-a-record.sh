#!/bin/bash
# Usage:
#   ./set-dns-records.sh example.com 203.0.113.10
#   ./set-dns-records.sh api.example.com 203.0.113.10
#
# Requirements: curl, jq
# DigitalOcean API Token must be set below.
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -euo pipefail

FULL_DOMAIN=$1
IP_ADDRESS=$2

# Require API token from environment
: "${DO_API_TOKEN:?❌ Environment variable DO_API_TOKEN not set. Please run: export DO_API_TOKEN=your_token}"

# ✅ Exit if domain has more than 2 dots (deep subdomain)
if [[ $(echo "$FULL_DOMAIN" | awk -F'.' '{print NF-1}') -gt 1 ]]; then
  echo "❌ Deep subdomains like $FULL_DOMAIN are not supported. Please use a root domain (example.com) or first-level (www.example.com)."
  exit 1
fi

if [ -z "$FULL_DOMAIN" ] || [ -z "$IP_ADDRESS" ]; then
  echo "Usage: $0 <domain|subdomain> <ip_address>"
  exit 1
fi

# --- Dependency checks ---
if ! command -v jq &>/dev/null; then
  echo "jq not found. Installing..."
  apt-get update -y
  apt-get install -y jq
fi

API_TOKEN=$DO_API_TOKEN
API="https://api.digitalocean.com/v2"

# --- Step 1: Extract root domain & record name ---
ROOT_DOMAIN=$(echo "$FULL_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

if [ "$FULL_DOMAIN" = "$ROOT_DOMAIN" ]; then
  RECORD_NAME="@"
else
  RECORD_NAME=${FULL_DOMAIN%.$ROOT_DOMAIN}
fi

echo "🌍 Root domain: $ROOT_DOMAIN"
echo "📝 Record name: $RECORD_NAME"
echo "➡️ Target IP: $IP_ADDRESS"

# --- Step 2: Ensure root domain exists ---
DOMAIN_DATA=$(curl -s -X GET "$API/domains/$ROOT_DOMAIN" \
  -H "Authorization: Bearer $API_TOKEN")

DOMAIN_EXISTS=$(echo "$DOMAIN_DATA" | jq -r '.domain.name // empty')

if [ "$DOMAIN_EXISTS" != "$ROOT_DOMAIN" ]; then
  echo "🌍 Domain $ROOT_DOMAIN not found. Creating..."
  DOMAIN_DATA=$(curl -s -X POST "$API/domains" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -d "{
      \"name\": \"$ROOT_DOMAIN\",
      \"ip_address\": \"$IP_ADDRESS\"
    }")
  echo "✅ Domain $ROOT_DOMAIN created."
else
  echo "✅ Domain $ROOT_DOMAIN already exists."
fi

# --- Step 3: Fetch all records once ---
ALL_RECORDS=$(curl -s -X GET "$API/domains/$ROOT_DOMAIN/records" \
  -H "Authorization: Bearer $API_TOKEN")

# --- Step 4: Ensure record function ---
ensure_a_record() {
  local NAME=$1
  local RECORD=$(echo "$ALL_RECORDS" | jq -r --arg NAME "$NAME" '
    .domain_records[]
    | select(.type=="A" and .name==$NAME)
    | @base64' | head -n1)

  if [ -n "$RECORD" ]; then
    RECORD_ID=$(echo "$RECORD" | base64 --decode | jq -r '.id')
    CURRENT_IP=$(echo "$RECORD" | base64 --decode | jq -r '.data')

    if [ "$CURRENT_IP" != "$IP_ADDRESS" ]; then
      echo "✏️ Updating A record for $NAME.$ROOT_DOMAIN ($CURRENT_IP → $IP_ADDRESS)..."
      curl -s -X PUT "$API/domains/$ROOT_DOMAIN/records/$RECORD_ID" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_TOKEN" \
        -d "{
          \"type\": \"A\",
          \"name\": \"$NAME\",
          \"data\": \"$IP_ADDRESS\",
          \"ttl\": 3600
        }" | jq .
      echo "✅ Updated $NAME.$ROOT_DOMAIN"
    else
      echo "👌 $NAME.$ROOT_DOMAIN already points to $IP_ADDRESS"
    fi
  else
    echo "➕ Creating A record for $NAME.$ROOT_DOMAIN -> $IP_ADDRESS..."
    curl -s -X POST "$API/domains/$ROOT_DOMAIN/records" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_TOKEN" \
      -d "{
        \"type\": \"A\",
        \"name\": \"$NAME\",
        \"data\": \"$IP_ADDRESS\",
        \"ttl\": 3600
      }" | jq .
    echo "✅ Created $NAME.$ROOT_DOMAIN"
  fi
}

# --- Step 5: Apply logic ---
if [ "$RECORD_NAME" = "@" ]; then
  # Root domain → ensure both @ and www
  ensure_a_record "@"
  ensure_a_record "www"
else
  # Subdomain → only ensure that specific subdomain
  ensure_a_record "$RECORD_NAME"
  ensure_a_record "www.$RECORD_NAME"
fi

echo "🎉 DNS setup complete for $FULL_DOMAIN"
