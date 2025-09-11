#!/bin/bash
# Secure script to login to GitHub Container Registry with nerdctl
# Auto-installs dependencies and configures credential helper on first run.
# Usage: ./ghcr-login.sh <github-username>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <github-username>"
  exit 1
fi

USERNAME=$1

# Check for jq
if ! command -v jq &>/dev/null; then
  echo "jq not found. Installing..."
  sudo apt-get update -y
  sudo apt-get install -y jq
fi

# Check for docker credential helper
if ! command -v docker-credential-secretservice &>/dev/null; then
  echo "docker-credential-secretservice not found. Installing..."
  sudo apt-get update -y
  sudo apt-get install -y golang-docker-credential-helpers
fi

# Determine config file location
if [ "$(id -u)" -eq 0 ]; then
  CONFIG_FILE="/etc/nerdctl/config.json"
else
  CONFIG_FILE="$HOME/.config/nerdctl/config.json"
fi

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG_FILE")"

# Configure credsStore if not present
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Configuring credential helper (secretservice)..."
  cat > "$CONFIG_FILE" <<EOF
{
  "auths": {},
  "credsStore": "secretservice"
}
EOF
else
  if ! grep -q '"credsStore"' "$CONFIG_FILE"; then
    echo "Adding credential helper (secretservice) to existing config..."
    tmpfile=$(mktemp)
    jq '. + {"credsStore":"secretservice"}' "$CONFIG_FILE" > "$tmpfile" && mv "$tmpfile" "$CONFIG_FILE"
  fi
fi

# Prompt securely for token (hidden input)
read -s -p "Enter GitHub Personal Access Token: " TOKEN
echo ""

# Login with nerdctl
echo "$TOKEN" | nerdctl login ghcr.io -u "$USERNAME" --password-stdin
