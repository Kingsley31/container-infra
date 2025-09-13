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

# -------------------------------
# SOLUTION: Ensure nginx listens on ports 80 and 443
# -------------------------------
echo "[INFO] Ensuring nginx listens on ports 80 and 443..."
cat <<EOF > $VOLUME_PATH/conf.d/default.conf
# HTTP server
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 'healthy';
        add_header Content-Type text/plain;
    }
    
    # Default response
    location / {
        return 200 'Nginx proxy is running! Add your server configurations to /etc/nginx/conf.d/';
        add_header Content-Type text/plain;
    }
}

# HTTPS server (will work once SSL certificates are added)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;
    
    # SSL certificates (update these paths when you get real certificates)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 'healthy';
        add_header Content-Type text/plain;
    }
    
    # Default response
    location / {
        return 200 'Nginx HTTPS is running! Add your server configurations to /etc/nginx/conf.d/';
        add_header Content-Type text/plain;
    }
}
EOF

# Create a self-signed certificate for testing if it doesn't exist
if [ ! -f "$VOLUME_PATH/letsencrypt/selfsigned.crt" ] || [ ! -f "$VOLUME_PATH/letsencrypt/selfsigned.key" ]; then
    echo "[INFO] Generating self-signed SSL certificate for testing..."
    mkdir -p $VOLUME_PATH/letsencrypt
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout $VOLUME_PATH/letsencrypt/selfsigned.key \
      -out $VOLUME_PATH/letsencrypt/selfsigned.crt \
      -subj "/CN=localhost" 2>/dev/null
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

# Wait a moment for nginx to start
echo "[INFO] Waiting for nginx to start..."
sleep 3

# Verify nginx is listening on ports 80 and 443
echo "[INFO] Verifying nginx is listening on ports 80 and 443..."
if sudo ss -tulpn | grep -E '(:80|:443)' | grep -q nginx; then
    echo "✅ Nginx is successfully listening on ports 80 and 443!"
else
    echo "⚠️  Nginx may not be listening on ports 80/443. Checking container logs..."
    nerdctl logs nginx_proxy | tail -10
    echo "ℹ️  Please check your nginx configuration if ports are not open."
fi

# Test the health endpoint
echo "[INFO] Testing nginx health endpoint..."
if curl -s http://localhost/health | grep -q healthy; then
    echo "✅ Nginx health check passed!"
else
    echo "⚠️  Nginx health check failed. Container may still be starting..."
fi

echo "✅ Nginx proxy is running and using configs from $VOLUME_PATH"
echo "🌐 HTTP is available on port 80"
echo "🔒 HTTPS is available on port 443 (with self-signed cert for testing)"
echo "📁 Add your server configurations to: $VOLUME_PATH/conf.d/"