#!/bin/bash
# run-nginx-proxy.sh
# Run nginx container with restart policy and mounted volumes.

set -e

VOLUME_PATH="$1"

if [[ -z "$VOLUME_PATH" ]]; then
    echo "Usage: $0 <volume_path>"
    echo "Example: $0 /home/username/nginx"
    exit 1
fi

# Ensure required directories exist
mkdir -p "$VOLUME_PATH/conf.d" "$VOLUME_PATH/letsencrypt" "$VOLUME_PATH/html"

# Stop and remove any existing container
if sudo nerdctl ps -a --format '{{.Names}}' | grep -q '^nginx_proxy$'; then
    echo "[INFO] Stopping existing nginx_proxy container..."
    sudo nerdctl stop nginx_proxy || true
    sudo nerdctl rm nginx_proxy || true
fi

# Run nginx container
echo "[INFO] Starting nginx_proxy container with volumes from $VOLUME_PATH"
sudo nerdctl run -d --name nginx_proxy \
  --restart always \
  --network nginx_network \
  -p 80:80 -p 443:443 \
  -v "$VOLUME_PATH/nginx.conf:/etc/nginx/nginx.conf" \
  -v "$VOLUME_PATH/conf.d:/etc/nginx/conf.d" \
  -v "$VOLUME_PATH/letsencrypt:/etc/letsencrypt" \
  -v "$VOLUME_PATH/html:/usr/share/nginx/html" \
  nginx:alpine

echo "[INFO] nginx_proxy is running with restart policy 'always'"
