#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -e



VOLUME_PATH="/etc/container-infra/nginx"
NGINX_CONTAINER_NAME="nginx_proxy"

echo "[INFO] Using Nginx volume path: $VOLUME_PATH"

# Ensure required directories exist
mkdir -p $VOLUME_PATH/conf.d
mkdir -p $VOLUME_PATH/letsencrypt
mkdir -p $VOLUME_PATH/html

# Ensure nginx.conf exists and is a file
if [ -d "$VOLUME_PATH/nginx.conf" ]; then
  echo "[ERROR] $VOLUME_PATH/nginx.conf is a directory, removing it..."
  rm -rf "$VOLUME_PATH/nginx.conf"
fi

if [ ! -f "$VOLUME_PATH/nginx.conf" ]; then
  echo "[WARN] $VOLUME_PATH/nginx.conf not found, creating a default one..."
  cat <<EOF > $VOLUME_PATH/nginx.conf
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
}
EOF
fi

# Ensure nginx_network exists
if ! nerdctl network ls | awk '{print $2}' | grep -q '^nginx_network$'; then
  echo "[INFO] Creating network: nginx_network"
  nerdctl network create nginx_network
else
  echo "[INFO] Network nginx_network already exists"
fi

# Stop existing container if running
if nerdctl ps -a --format '{{.Names}}' | grep -q '^nginx_proxy$'; then
  echo "[INFO] Stopping and removing existing nginx_proxy container..."
  nerdctl stop nginx_proxy || true
  nerdctl rm nginx_proxy || true
fi

# Run nginx container with nerdctl
echo "[INFO] Starting nginx_proxy container with volumes from $VOLUME_PATH"
nerdctl run -d \
  --name $NGINX_CONTAINER_NAME \
  --network host \
  --restart always \
  -v $VOLUME_PATH/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $VOLUME_PATH/conf.d:/etc/nginx/conf.d \
  -v $VOLUME_PATH/letsencrypt:/etc/letsencrypt \
  -v $VOLUME_PATH/html:/usr/share/nginx/html \
  docker.io/library/nginx:alpine

echo "✅ Nginx proxy is running and using configs from $VOLUME_PATH"
