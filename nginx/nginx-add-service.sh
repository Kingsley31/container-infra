#!/bin/bash
set -euo pipefail

# Auto-elevate with sudo if not root
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# Usage examples:
# ./nginx-add-service.sh /opt/nginx myservice 8080 mycontainer_v1
# ./nginx-add-service.sh /opt/nginx myservice 8080 mycontainer_v1 mydomain.com
# ./nginx-add-service.sh /opt/nginx myservice 8080 mycontainer_v1 /

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <nginx_base_dir> <service_name> <service_port> <container_name> [domain_name]"
    echo "Examples:"
    echo "  $0 /opt/nginx myservice 8080 mycontainer_v1             # default: myservice.example.com"
    echo "  $0 /opt/nginx myservice 8080 mycontainer_v1 mydomain.com  # custom domain"
    echo "  $0 /opt/nginx myservice 8080 mycontainer_v1 /            # uses example.com and www.example.com"
    exit 1
fi

NGINX_BASE_DIR=$1
SERVICE_NAME=$2
SERVICE_PORT=$3
CONTAINER_NAME=$4
DOMAIN_INPUT=${5:-""}
NGINX_CONF_DIR="$NGINX_BASE_DIR/conf.d"
NGINX_CONTAINER="nginx_proxy"

# Make sure conf.d exists
mkdir -p "$NGINX_CONF_DIR"

# Determine domain(s)
if [[ "$DOMAIN_INPUT" == "/" ]]; then
    DOMAIN_NAME="example.com"
    DOMAIN_ALIAS="www.example.com"
elif [[ -z "$DOMAIN_INPUT" ]]; then
    DOMAIN_NAME="$SERVICE_NAME.example.com"
    DOMAIN_ALIAS=""
else
    DOMAIN_INPUT="${DOMAIN_INPUT%/}"
    DOMAIN_NAME="$DOMAIN_INPUT"
    DOMAIN_ALIAS=""
fi

# Validate domain
if ! [[ "$DOMAIN_NAME" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Error: Invalid domain name '$DOMAIN_NAME'."
    exit 1
fi
if [[ -n "$DOMAIN_ALIAS" ]] && ! [[ "$DOMAIN_ALIAS" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Error: Invalid domain alias '$DOMAIN_ALIAS'."
    exit 1
fi

NGINX_CONF_FILE="$NGINX_CONF_DIR/$SERVICE_NAME.conf"
CERTBOT_DIR="$NGINX_BASE_DIR/letsencrypt"
mkdir -p "$CERTBOT_DIR" "$NGINX_BASE_DIR/html"

NGINX_MAIN_CONF="$NGINX_BASE_DIR/nginx.conf"
if [[ ! -f "$NGINX_MAIN_CONF" ]]; then
    echo "No nginx.conf found — generating default one at $NGINX_MAIN_CONF"
    tee "$NGINX_MAIN_CONF" > /dev/null <<'EOF'
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout  65;

    include /etc/nginx/conf.d/*.conf;
}
EOF
fi

echo "Configuring service '$SERVICE_NAME' with container '$CONTAINER_NAME' on port $SERVICE_PORT..."
echo "Domain: $DOMAIN_NAME"
if [[ -n "$DOMAIN_ALIAS" ]]; then
    echo "Domain Alias: $DOMAIN_ALIAS"
fi

# 1. Install certbot if missing
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt update
    apt install -y certbot
fi

# 2. Obtain or renew SSL certificate
CERT_PATH="$CERTBOT_DIR/live/$DOMAIN_NAME"
if [[ -n "$DOMAIN_ALIAS" ]]; then
    certbot certonly --webroot -w "$NGINX_BASE_DIR/html" \
        --non-interactive --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN_NAME" -d "$DOMAIN_ALIAS" \
        --config-dir "$CERTBOT_DIR" \
        --logs-dir "$CERTBOT_DIR/logs" \
        --work-dir "$CERTBOT_DIR/work" \
        || echo "Certificate may already exist or certbot failed."
else
    certbot certonly --webroot -w "$NGINX_BASE_DIR/html" \
        --non-interactive --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN_NAME" \
        --config-dir "$CERTBOT_DIR" \
        --logs-dir "$CERTBOT_DIR/logs" \
        --work-dir "$CERTBOT_DIR/work" \
        || echo "Certificate may already exist or certbot failed."
fi

# 3. Write or update Nginx config with SSL + load balancing
if [[ -f "$NGINX_CONF_FILE" ]]; then
    echo "[INFO] Updating existing config $NGINX_CONF_FILE"
    # Append container to upstream if not already listed
    if ! grep -q "server $CONTAINER_NAME:$SERVICE_PORT;" "$NGINX_CONF_FILE"; then
        sed -i "/upstream ${SERVICE_NAME}_upstream {/a \    server $CONTAINER_NAME:$SERVICE_PORT;" "$NGINX_CONF_FILE"
    fi
else
    echo "[INFO] Creating new config $NGINX_CONF_FILE"
    tee "$NGINX_CONF_FILE" > /dev/null <<EOF
upstream ${SERVICE_NAME}_upstream {
    server $CONTAINER_NAME:$SERVICE_PORT;
}

server {
    listen 80;
    server_name $DOMAIN_NAME${DOMAIN_ALIAS:+ $DOMAIN_ALIAS};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME${DOMAIN_ALIAS:+ $DOMAIN_ALIAS};

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
fi

echo "Nginx config updated at $NGINX_CONF_FILE"

# 4. Reload Nginx container
echo "Reloading Nginx container..."
nerdctl exec "$NGINX_CONTAINER" nginx -s reload

echo "✅ Service '$SERVICE_NAME' with container '$CONTAINER_NAME' configured at $DOMAIN_NAME${DOMAIN_ALIAS:+, $DOMAIN_ALIAS}."
