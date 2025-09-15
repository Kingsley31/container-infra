#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -euo pipefail

: "${GHCR_TOKEN:?❌ Environment variable GHCR_TOKEN not set. Please run: export GHCR_TOKEN=your_github_token}"
: "${GHCR_USERNAME:?❌ Environment variable GHCR_USERNAME not set. Please run: export GHCR_USERNAME=your_github_username}"


USERNAME=$GHCR_USERNAME
TOKEN=$GHCR_TOKEN

# --- Dependency checks ---
if ! command -v jq &>/dev/null; then
  echo "jq not found. Installing..."
  apt-get update -y
  apt-get install -y jq
fi

if ! command -v docker-credential-store &>/dev/null; then
  echo "docker credential helpers not found. Installing..."
  apt-get update -y
  apt-get install -y golang-docker-credential-helpers
fi

# --- Decide which credsStore to use ---
if command -v docker-credential-secretservice &>/dev/null && pgrep -x "dbus-daemon" >/dev/null; then
  CRED_STORE="secretservice"
else
  CRED_STORE="store"
fi

echo "Using credential helper: $CRED_STORE"

# --- Determine config file location ---
if [ "$(id -u)" -eq 0 ]; then
  CONFIG_FILE="/etc/nerdctl/config.json"
else
  CONFIG_FILE="$HOME/.config/nerdctl/config.json"
fi

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG_FILE")"

# --- Write config with credsStore ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Creating new nerdctl config with $CRED_STORE..."
  cat > "$CONFIG_FILE" <<EOF
{
  "auths": {},
  "credsStore": "$CRED_STORE"
}
EOF
else
  if ! grep -q '"credsStore"' "$CONFIG_FILE"; then
    echo "Adding $CRED_STORE credential helper to existing config..."
    tmpfile=$(mktemp)
    jq --arg cs "$CRED_STORE" '. + {"credsStore":$cs}' "$CONFIG_FILE" > "$tmpfile" && mv "$tmpfile" "$CONFIG_FILE"
  else
    echo "Updating credential helper to $CRED_STORE..."
    tmpfile=$(mktemp)
    jq --arg cs "$CRED_STORE" '.credsStore = $cs' "$CONFIG_FILE" > "$tmpfile" && mv "$tmpfile" "$CONFIG_FILE"
  fi
fi


# --- Login with nerdctl ---
echo "$TOKEN" | nerdctl login ghcr.io -u "$USERNAME" --password-stdin
