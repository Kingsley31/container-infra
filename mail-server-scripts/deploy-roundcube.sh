#!/usr/bin/env bash
set -euo pipefail


# Require root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# Check if env file path was provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 path_to_env_file"
  exit 1
fi

ENV_FILE="$1"

# Verify env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: Environment file '$ENV_FILE' does not exist."
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
mkdir -p "$VOLUME_BASE/var/www/html"
mkdir -p "$VOLUME_BASE/var/roundcube/config"
mkdir -p "$VOLUME_BASE/tmp/roundcube-temp"

# Set Roundcube version (change if needed, e.g. 1.6.7)
ROUNDCUBE_VERSION="latest"

# Run Roundcube container
nerdctl run -d \
  --name roundcube \
  --network host \
  --restart always \
  --env-file "$ENV_FILE" \
  -p 9000:80 \
  -v "$VOLUME_BASE/var/www/html:/var/www/html" \
  -v "$VOLUME_BASE/var/roundcube/config:/var/roundcube/config" \
  -v "$VOLUME_BASE/tmp/roundcube-temp:/tmp/roundcube-temp" \
  roundcube/roundcubemail:"$ROUNDCUBE_VERSION"
