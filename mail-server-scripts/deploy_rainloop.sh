#!/usr/bin/env bash
set -euo pipefail

# Require root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# Ensure nerdctl is installed
if ! command -v nerdctl >/dev/null 2>&1; then
  echo "Error: nerdctl not found. Please install containerd/nerdctl first."
  exit 1
fi

# Define base volume path
VOLUME_BASE="/etc/container-infra"

# Create directories if they don't exist
mkdir -p "$VOLUME_BASE/rainloop/data"

# Stop and remove existing container if it exists
if nerdctl ps -a --format '{{.Names}}' | grep -q '^roundcube$'; then
  echo "Removing existing roundcube container..."
  nerdctl rm -f roundcube
fi

# Run Roundcube container with Apache override
echo "🚀 Starting Rainloop container..."
sudo nerdctl run -d \
  --name roundcube \
  -p 127.0.0.1:8080:80 \
  -v "$VOLUME_BASE/rainloop/data:/rainloop/data" \
  --restart unless-stopped \
  hardware/rainloop:latest