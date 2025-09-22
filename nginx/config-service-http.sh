#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -euo pipefail


if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <service_name> <service_port> <container_name> [domain_name]"
    exit 1
fi

NGINX_BASE_DIR="/etc/container-infra/nginx"
SERVICE_NAME=$1
SERVICE_PORT=$2
CONTAINER_NAME=$3
DOMAIN_INPUT=${4:-""}

NGINX_CONF_DIR="$NGINX_BASE_DIR/conf.d"
NGINX_CONTAINER="nginx_proxy"

# --- Step 1: Validate container ---
if ! nerdctl ps --format "{{.Names}}" | grep -qw "$CONTAINER_NAME"; then
    echo "❌ Container '$CONTAINER_NAME' is not running."
    exit 1
fi

# --- Step 2: Verify Nginx can reach container ---
if ! nerdctl exec "$NGINX_CONTAINER" wget -qO- http://127.0.0.1:$SERVICE_PORT/ >/dev/null 2>&1; then
    echo "❌ Nginx cannot reach container '$CONTAINER_NAME' on '127.0.0.1:$SERVICE_PORT'."
    exit 1
fi
echo "✅ Nginx can reach container '$CONTAINER_NAME' on '127.0.0.1:$SERVICE_PORT'."

# --- Step 3: Minimal domain processing ---
if [[ "$DOMAIN_INPUT" == "/" ]]; then
    DOMAIN_NAME="energymixtech.com"
elif [[ -z "$DOMAIN_INPUT" ]]; then
    DOMAIN_NAME="$SERVICE_NAME.energymixtech.com"
else
    DOMAIN_INPUT="${DOMAIN_INPUT%/}"
    if ! [[ "$DOMAIN_INPUT" =~ ^[A-Za-z0-9.-]+$ ]]; then
        echo "❌ Invalid domain name '$DOMAIN_INPUT'."
        exit 1
    fi
    DOMAIN_NAME="$DOMAIN_INPUT"
fi
DOMAIN_ALIAS="www.$DOMAIN_NAME"

# --- Step 4: Prepare directories ---
mkdir -p "$NGINX_CONF_DIR" "$NGINX_BASE_DIR/html"

# --- Step 5: Write temporary HTTP config with upstream ---
NGINX_CONF_FILE="$NGINX_CONF_DIR/$SERVICE_NAME.conf"
tee "$NGINX_CONF_FILE" > /dev/null <<EOF
upstream ${SERVICE_NAME}_upstream {
    server 127.0.0.1:$SERVICE_PORT;
}

server {
    listen 80;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;
    client_max_body_size 50M;
    proxy_request_buffering off;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        proxy_pass http://${SERVICE_NAME}_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# --- Step 5: Reload Nginx ---
echo "Reloading nginx container..."
sleep 10
nerdctl exec "$NGINX_CONTAINER" nginx -t
nerdctl exec "$NGINX_CONTAINER" nginx -s reload
echo "✅ Temporary HTTP config with upstream applied."

# --- Step 6: Validate nginx container ---
echo "Checking that nginx container is still running..."
sleep 10
if ! nerdctl ps --format "{{.Names}}" | grep -qw "$NGINX_CONTAINER"; then
    echo "❌ Container '$NGINX_CONTAINER' is not running."
    exit 1
fi
echo "✅ Nginx container is still running!!!."