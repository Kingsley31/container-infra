#!/bin/bash
# DigitalOcean Droplet PTR Record Manager (Clean Version)
# Sets PTR records for floating IPs and updates hostname

set -euo pipefail

# Require sudo (needed for hostnamectl)
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

if [ $# -ne 2 ]; then
  echo "Usage: $0 <droplet_id> <fqdn>"
  exit 1
fi

DROPLET_ID="$1"
FQDN="$2"

if [ -z "${DO_API_TOKEN:-}" ]; then
  echo "❌ DO_API_TOKEN environment variable is not set"
  exit 1
fi

API="https://api.digitalocean.com/v2"

echo "🔎 Fetching droplet $DROPLET_ID..."
DROPLET_JSON=$(curl -s -H "Authorization: Bearer $DO_API_TOKEN" \
  "$API/droplets/$DROPLET_ID")

if ! echo "$DROPLET_JSON" | jq -e '.droplet.id' >/dev/null 2>&1; then
  echo "❌ Droplet not found or API error"
  exit 1
fi

NAME=$(echo "$DROPLET_JSON" | jq -r '.droplet.name')
IMAGE=$(echo "$DROPLET_JSON" | jq -r '.droplet.image.distribution + " " + .droplet.image.name')
REGION=$(echo "$DROPLET_JSON" | jq -r '.droplet.region.slug')
IP=$(echo "$DROPLET_JSON" | jq -r '.droplet.networks.v4[] | select(.type=="public") | .ip_address')

echo "📌 Droplet Info:"
echo "   Name:   $NAME"
echo "   Image:  $IMAGE"
echo "   Region: $REGION"
echo "   Public IPv4: $IP"

echo "⚙️ Updating local hostname to $FQDN..."
hostnamectl set-hostname "$FQDN"
echo "✓ Hostname set"

echo "🔎 Checking if $IP is a floating IP..."
FLOATING_JSON=$(curl -s -H "Authorization: Bearer $DO_API_TOKEN" \
  "$API/floating_ips/$IP")

if echo "$FLOATING_JSON" | jq -e '.floating_ip' >/dev/null 2>&1; then
  echo "🌐 $IP is a floating IP, setting PTR record..."
  RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PUT \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"ptr_record\":\"$FQDN\"}" \
    "$API/floating_ips/$IP/ptr")

  HTTP_STATUS=$(echo "$RESPONSE" | sed -n 's/^HTTP_STATUS://p')
  BODY=$(echo "$RESPONSE" | sed '/^HTTP_STATUS:/d')

  if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    echo "✅ PTR record set successfully: $IP -> $FQDN"
  else
    echo "❌ Failed to set PTR record"
    echo "Status: $HTTP_STATUS"
    echo "Body: $BODY"
    exit 1
  fi
else
  echo "⚠️ $IP is NOT a floating IP."
  echo "DigitalOcean only supports PTR records on floating IPs."
  echo "You may need to assign a floating IP to this droplet first."
fi
