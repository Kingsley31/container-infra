#!/bin/bash
# Secure script to login to GitHub Container Registry with nerdctl
# Auto-installs dependencies and configures credential helper based on environment.
# Usage: ./ghcr-login.sh <github-username>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <github-username>"
  exit 1
fi

USERNAME=$1

# --- Dependency checks ---
if ! command -v jq &>/dev/null; then
  echo "jq not found. Installing..."
  sudo apt-get update -y
  sudo apt-get install -y jq
fi

if ! command -v docker-credential-store &>/dev/null; then
  echo "docker credential helpers not found. Installing..."
  sudo apt-get update -y
  sudo apt-get install -y golang-docker-credential-helpers
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

# --- Secure token prompt ---
read -s -p "Enter GitHub Personal Access Token: " TOKEN
echo ""

# --- Login with nerdctl ---
echo "$TOKEN" | nerdctl login ghcr.io -u "$USERNAME" --password-stdin
