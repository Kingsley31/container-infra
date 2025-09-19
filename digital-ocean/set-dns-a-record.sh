#!/bin/bash
# Usage:
#   ./set-dns-records.sh example.com 203.0.113.10
#   ./set-dns-records.sh api.example.com 203.0.113.10
#
# Requirements: curl, jq
# DigitalOcean API Token must be set as DO_API_TOKEN environment variable.

set -euo pipefail

# Validate inputs
if [ $# -ne 2 ]; then
  echo "Usage: $0 <domain|subdomain> <ip_address>"
  exit 1
fi

FULL_DOMAIN=$1
IP_ADDRESS=$2

# Validate IP address format
if ! [[ "$IP_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid IP address format: $IP_ADDRESS"
  exit 1
fi

# Require API token from environment
: "${DO_API_TOKEN:?❌ Environment variable DO_API_TOKEN not set. Please run: export DO_API_TOKEN=your_token}"

# --- Dependency checks ---
if ! command -v jq &>/dev/null; then
  echo "jq not found. Installing..."
  sudo apt-get update -y
  sudo apt-get install -y jq
fi

API_TOKEN="$DO_API_TOKEN"
API="https://api.digitalocean.com/v2"

# --- Step 1: Extract root domain & record name ---
if [[ "$FULL_DOMAIN" =~ ^[^.]+\.[^.]+$ ]]; then
  # Simple domain like example.com
  ROOT_DOMAIN="$FULL_DOMAIN"
  RECORD_NAME="@"
  CREATE_WWW=true
else
  # Subdomain - extract root domain (last two parts)
  ROOT_DOMAIN=$(echo "$FULL_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
  RECORD_NAME="${FULL_DOMAIN%.$ROOT_DOMAIN}"
  
  # Validate that we actually extracted a subdomain
  if [ "$FULL_DOMAIN" = "$RECORD_NAME" ] || [ -z "$RECORD_NAME" ]; then
    echo "❌ Failed to parse domain: $FULL_DOMAIN"
    echo "💡 Please use format: subdomain.example.com or example.com"
    exit 1
  fi
  
  # Only create www version for non-www subdomains that aren't too deep
  if [[ "$RECORD_NAME" != "www" ]] && [[ $(echo "$RECORD_NAME" | tr -cd '.' | wc -c) -eq 0 ]]; then
    CREATE_WWW=true
  else
    CREATE_WWW=false
  fi
fi

echo "🌍 Root domain: $ROOT_DOMAIN"
echo "📝 Record name: $RECORD_NAME"
echo "➡️ Target IP: $IP_ADDRESS"
echo "🌐 Create www version: $CREATE_WWW"

# --- Step 2: Check if domain exists ---
DOMAIN_RESPONSE=$(curl -s -w "%{http_code}" -X GET "$API/domains/$ROOT_DOMAIN" \
  -H "Authorization: Bearer $API_TOKEN")

HTTP_CODE="${DOMAIN_RESPONSE: -3}"
DOMAIN_DATA="${DOMAIN_RESPONSE%???}"

if [ "$HTTP_CODE" -eq 404 ]; then
  echo "❌ Domain $ROOT_DOMAIN not found in DigitalOcean."
  echo "💡 Please create the domain in DigitalOcean control panel first."
  exit 1
elif [ "$HTTP_CODE" -ne 200 ]; then
  echo "❌ API Error: HTTP $HTTP_CODE"
  echo "$DOMAIN_DATA" | jq . 2>/dev/null || echo "$DOMAIN_DATA"
  exit 1
fi

# --- Step 3: Fetch all records ---
RECORDS_RESPONSE=$(curl -s -w "%{http_code}" -X GET "$API/domains/$ROOT_DOMAIN/records" \
  -H "Authorization: Bearer $API_TOKEN")

HTTP_CODE="${RECORDS_RESPONSE: -3}"
ALL_RECORDS="${RECORDS_RESPONSE%???}"

if [ "$HTTP_CODE" -ne 200 ]; then
  echo "❌ Failed to fetch DNS records: HTTP $HTTP_CODE"
  exit 1
fi

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
      UPDATE_RESPONSE=$(curl -s -w "%{http_code}" -X PUT "$API/domains/$ROOT_DOMAIN/records/$RECORD_ID" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_TOKEN" \
        -d "{
          \"type\": \"A\",
          \"name\": \"$NAME\",
          \"data\": \"$IP_ADDRESS\",
          \"ttl\": 300
        }")
      
      HTTP_CODE="${UPDATE_RESPONSE: -3}"
      if [ "$HTTP_CODE" -ne 200 ]; then
        echo "❌ Failed to update record: HTTP $HTTP_CODE"
        exit 1
      fi
      echo "✅ Updated $NAME.$ROOT_DOMAIN"
    else
      echo "👌 $NAME.$ROOT_DOMAIN already points to $IP_ADDRESS"
    fi
  else
    echo "➕ Creating A record for $NAME.$ROOT_DOMAIN -> $IP_ADDRESS..."
    CREATE_RESPONSE=$(curl -s -w "%{http_code}" -X POST "$API/domains/$ROOT_DOMAIN/records" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_TOKEN" \
      -d "{
        \"type\": \"A\",
        \"name\": \"$NAME\",
        \"data\": \"$IP_ADDRESS\",
        \"ttl\": 300
      }")
    
    HTTP_CODE="${CREATE_RESPONSE: -3}"
    if [ "$HTTP_CODE" -ne 201 ]; then
      echo "❌ Failed to create record: HTTP $HTTP_CODE"
      exit 1
    fi
    echo "✅ Created $NAME.$ROOT_DOMAIN"
  fi
}

# --- Step 5: Apply logic ---
ensure_a_record "$RECORD_NAME"

# Create www version for appropriate domains
if [ "$CREATE_WWW" = true ]; then
  if [ "$RECORD_NAME" = "@" ]; then
    # For root domain, create www record
    ensure_a_record "www"
  else
    # For subdomains, create www.subdomain record
    ensure_a_record "www.$RECORD_NAME"
  fi
fi

echo "🎉 DNS setup complete for:"
echo "   → $FULL_DOMAIN -> $IP_ADDRESS"
if [ "$CREATE_WWW" = true ]; then
  if [ "$RECORD_NAME" = "@" ]; then
    echo "   → www.$ROOT_DOMAIN -> $IP_ADDRESS"
  else
    echo "   → www.$FULL_DOMAIN -> $IP_ADDRESS"
  fi
fi