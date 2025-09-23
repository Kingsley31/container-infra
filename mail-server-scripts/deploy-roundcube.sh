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
mkdir -p "$VOLUME_BASE/apache"

# Create a custom Apache ports.conf to force 8080
cat > "$VOLUME_BASE/apache/ports.conf" <<'EOF'
Listen 8080
<IfModule ssl_module>
    Listen 8443
</IfModule>
<IfModule mod_gnutls.c>
    Listen 8443
</IfModule>
EOF

# Roundcube version
ROUNDCUBE_VERSION="1.6.11-fpm"
CUSTOM_IMAGE="roundcube/roundcubemail:${ROUNDCUBE_VERSION}"

# Stop and remove existing container if it exists
if nerdctl ps -a --format '{{.Names}}' | grep -q '^roundcube$'; then
  echo "Removing existing roundcube container..."
  nerdctl rm -f roundcube
fi

# Run Roundcube container with Apache override
echo "🚀 Starting Roundcube container..."
nerdctl run -d \
  --name roundcube \
  --network host \
  --restart always \
  --env-file "$ENV_FILE" \
  -v "$VOLUME_BASE/var/www/html:/var/www/html" \
  -v "$VOLUME_BASE/var/roundcube/config:/var/roundcube/config" \
  -v "$VOLUME_BASE/tmp/roundcube-temp:/tmp/roundcube-temp" \
  -v "$VOLUME_BASE/apache/ports.conf:/etc/apache2/ports.conf:ro" \
  "${CUSTOM_IMAGE}"
