#!/bin/bash
set -e

# Check if volume path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <volume-path>"
  echo "Example: $0 /home/username/nginx"
  exit 1
fi

VOLUME_PATH=$1

echo "[INFO] Using Nginx volume path: $VOLUME_PATH"

# Ensure required directories exist
mkdir -p $VOLUME_PATH/conf.d
mkdir -p $VOLUME_PATH/letsencrypt
mkdir -p $VOLUME_PATH/html

# Ensure nginx.conf exists
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
if ! sudo nerdctl network ls | awk '{print $2}' | grep -q '^nginx_network$'; then
  echo "[INFO] Creating network: nginx_network"
  sudo nerdctl network create nginx_network
else
  echo "[INFO] Network nginx_network already exists"
fi

# Stop existing container if running
if sudo nerdctl ps -a --format '{{.Names}}' | grep -q '^nginx_proxy$'; then
  echo "[INFO] Stopping and removing existing nginx_proxy container..."
  sudo nerdctl stop nginx_proxy || true
  sudo nerdctl rm nginx_proxy || true
fi

# Run nginx container with nerdctl
echo "[INFO] Starting nginx_proxy container with volumes from $VOLUME_PATH"
sudo nerdctl run -d \
  --name nginx_proxy \
  --network nginx_network \
  --restart always \
  -p 80:80 -p 443:443 \
  -v $VOLUME_PATH:/etc/nginx \
  -v $VOLUME_PATH/letsencrypt:/etc/letsencrypt \
  -v $VOLUME_PATH/html:/usr/share/nginx/html \
  nginx:alpine

echo "✅ Nginx proxy is running and using configs from $VOLUME_PATH"
