#!/bin/bash
set -euo pipefail

# Auto-elevate with sudo if not root
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# --- Step 0: Validate required arguments ---
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <nginx_base_dir> <service_name> <service_port> <container_name> [domain_name]"
    echo "Examples:"
    echo "  $0 /opt/nginx myservice 8080 mycontainer_v1"
    echo "  $0 /opt/nginx myservice 8080 mycontainer_v1 mydomain.com"
    echo "  $0 /opt/nginx myservice 8080 mycontainer_v1 /"
    exit 1
fi

NGINX_BASE_DIR=$1
SERVICE_NAME=$2
SERVICE_PORT=$3
CONTAINER_NAME=$4
DOMAIN_INPUT=${5:-""}
NGINX_CONF_DIR="$NGINX_BASE_DIR/conf.d"
NGINX_CONTAINER="nginx_proxy"

# --- Step 1: Check service container is running ---
if ! nerdctl ps --format "{{.Names}}" | grep -qw "$CONTAINER_NAME"; then
    echo "❌ Container '$CONTAINER_NAME' is not running."
    exit 1
fi

# --- Step 2: Check container is listening on expected port ---
if ! nerdctl exec "$CONTAINER_NAME" sh -c "netstat -tln | grep ':$SERVICE_PORT ' >/dev/null"; then
    echo "❌ Container '$CONTAINER_NAME' is not listening on port $SERVICE_PORT."
    exit 1
fi

# --- Step 3: Prepare directories ---
mkdir -p "$NGINX_CONF_DIR"
CERTBOT_DIR="$NGINX_BASE_DIR/letsencrypt"
mkdir -p "$CERTBOT_DIR" "$NGINX_BASE_DIR/html"

# --- Step 4: Determine domain(s) ---
if [[ "$DOMAIN_INPUT" == "/" ]]; then
    DOMAIN_NAME="energymixtech.com"
elif [[ -z "$DOMAIN_INPUT" ]]; then
    DOMAIN_NAME="$SERVICE_NAME.energymixtech.com"
else
    DOMAIN_INPUT="${DOMAIN_INPUT%/}"
    if ! [[ "$DOMAIN_INPUT" =~ ^[A-Za-z0-9.-]+$ ]]; then
        echo "❌ Invalid domain name '$DOMAIN_INPUT'. Allowed: letters, numbers, hyphens, dots."
        exit 1
    fi
    DOMAIN_NAME="$DOMAIN_INPUT"
fi

# Always add www alias
DOMAIN_ALIAS="www.$DOMAIN_NAME"

# --- Step 5: Create temporary HTTP-only Nginx config ---
NGINX_CONF_FILE="$NGINX_CONF_DIR/$SERVICE_NAME.conf"
tee "$NGINX_CONF_FILE" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 502;
    }
}
EOF

# Reload Nginx
nerdctl exec "$NGINX_CONTAINER" nginx -t
nerdctl exec "$NGINX_CONTAINER" nginx -s reload
echo "✅ Temporary HTTP config applied."

# --- Step 6: Verify connectivity from Nginx to container ---
sleep 10
if ! nerdctl exec "$NGINX_CONTAINER" wget -qO- http://$CONTAINER_NAME:$SERVICE_PORT/ >/dev/null 2>&1; then
    echo "❌ Nginx cannot reach container '$CONTAINER_NAME:$SERVICE_PORT'. Ensure it is on the same network."
    exit 1
fi
echo "✅ Nginx can reach container '$CONTAINER_NAME:$SERVICE_PORT'."

# --- Step 7: Obtain SSL certificate ---
CERT_PATH="$CERTBOT_DIR/live/$DOMAIN_NAME"
certbot certonly --webroot -w "$NGINX_BASE_DIR/html" \
    --non-interactive --agree-tos \
    --register-unsafely-without-email \
    -d "$DOMAIN_NAME" -d "$DOMAIN_ALIAS" \
    --config-dir "$CERTBOT_DIR" \
    --logs-dir "$CERTBOT_DIR/logs" \
    --work-dir "$CERTBOT_DIR/work" \
    || echo "⚠ Certificate may already exist or certbot failed."

# --- Step 8: Write final HTTPS config ---
tee "$NGINX_CONF_FILE" > /dev/null <<EOF
upstream ${SERVICE_NAME}_upstream {
    server $CONTAINER_NAME:$SERVICE_PORT;
}

server {
    listen 80;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;

    ssl_certificate $CERT_PATH/fullchain.pem;
    ssl_certificate_key $CERT_PATH/privkey.pem;

    location / {
        proxy_pass http://${SERVICE_NAME}_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# --- Step 9: Reload Nginx with final config ---
nerdctl exec "$NGINX_CONTAINER" nginx -t
nerdctl exec "$NGINX_CONTAINER" nginx -s reload

echo "✅ Service '$SERVICE_NAME' configured at $DOMAIN_NAME and $DOMAIN_ALIAS."
