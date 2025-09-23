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
echo "$IP  $FQDN" | sudo tee -a /etc/hosts
echo "✓ Hostname set"

# -------------------------------------------------
# 3. Issue rename action
# -------------------------------------------------
echo "🔄 Sending rename action request..."
RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DO_API_TOKEN" \
  -d "{\"type\":\"rename\",\"name\":\"$FQDN\"}" \
  "https://api.digitalocean.com/v2/droplets/${DROPLET_ID}/actions")

# Extract the action ID
ACTION_ID=$(echo "$RESPONSE" | jq -r '.action.id // empty')

if [[ -z "$ACTION_ID" ]]; then
  echo "❌ Failed to initiate rename action. Response:"
  echo "$RESPONSE"
  exit 1
fi

echo "✅ Rename action started (ID: $ACTION_ID). Waiting for completion..."

# -------------------------------------------------
# 4. Poll action status
# -------------------------------------------------
while true; do
  STATUS=$(curl -s -H "Authorization: Bearer $DO_API_TOKEN" \
    "$API/actions/${ACTION_ID}" | jq -r '.action.status')

  case "$STATUS" in
    completed)
      echo "🎉 Droplet $DROPLET_ID successfully renamed to $FQDN."
      break
      ;;
    errored)
      echo "❌ Rename action errored. Check the DigitalOcean dashboard for details."
      exit 1
      ;;
    *)
      echo "⏳ Current status: $STATUS – checking again in 5 seconds..."
      sleep 5
      ;;
  esac
done
