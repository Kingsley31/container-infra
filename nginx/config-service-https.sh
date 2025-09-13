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
LETSENCRYPT_DIR="$NGINX_BASE_DIR/letsencrypt"

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

# --- Step 3: Domain processing ---
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

echo "🔐 Configuring HTTPS for domain: $DOMAIN_NAME (alias: $DOMAIN_ALIAS)"

# --- Step 4: Prepare directories ---
mkdir -p "$NGINX_CONF_DIR" "$NGINX_BASE_DIR/html" "$LETSENCRYPT_DIR"

# --- Step 5: Write temporary HTTP config for ACME challenges ---
NGINX_CONF_FILE="$NGINX_CONF_DIR/$SERVICE_NAME.conf"
tee "$NGINX_CONF_FILE" > /dev/null <<EOF
upstream ${SERVICE_NAME}_upstream {
    server 127.0.0.1:$SERVICE_PORT;
}

server {
    listen 80;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

# --- Step 6: Reload Nginx for ACME challenges ---
echo "🔄 Reloading nginx for ACME challenges..."
nerdctl exec "$NGINX_CONTAINER" nginx -t
nerdctl exec "$NGINX_CONTAINER" nginx -s reload
sleep 3

# --- Step 7: Obtain SSL certificate with Certbot ---
echo "📜 Obtaining SSL certificate for $DOMAIN_NAME..."
if ! command -v certbot &> /dev/null; then
    echo "❌ Certbot is not installed. Installing..."
    sudo apt update
    sudo apt install -y certbot
fi

# Use the host path that is mounted to the container's /usr/share/nginx/html
HOST_WEBROOT_PATH="$NGINX_BASE_DIR/html"

# Run certbot to obtain certificate using the host's webroot path
if sudo certbot certonly --webroot \
    --non-interactive \
    --agree-tos \
    --email admin@energymixtech.com \
    --domains "$DOMAIN_NAME" \
    --domains "$DOMAIN_ALIAS" \
    --webroot-path "$HOST_WEBROOT_PATH" \
    --config-dir "$LETSENCRYPT_DIR" \
    --work-dir "$LETSENCRYPT_DIR/work" \
    --logs-dir "$LETSENCRYPT_DIR/logs"; then
    
    echo "✅ SSL certificate obtained successfully!"
else
    echo "❌ Failed to obtain SSL certificate. Check DNS settings and try again."
    echo "💡 Make sure:"
    echo "   1. Your domain points to this server's IP address"
    echo "   2. Port 80 is open and accessible from the internet"
    echo "   3. The webroot path $HOST_WEBROOT_PATH exists and is writable"
    exit 1
fi

# --- Step 8: Write final HTTPS configuration ---
echo "🔧 Writing final HTTPS configuration..."
tee "$NGINX_CONF_FILE" > /dev/null <<EOF
upstream ${SERVICE_NAME}_upstream {
    server 127.0.0.1:$SERVICE_PORT;
}

server {
    listen 80;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME $DOMAIN_ALIAS;

    ssl_certificate $LETSENCRYPT_DIR/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key $LETSENCRYPT_DIR/live/$DOMAIN_NAME/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        proxy_pass http://${SERVICE_NAME}_upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF

# --- Step 9: Final Nginx reload ---
echo "🔄 Final nginx reload with HTTPS configuration..."
nerdctl exec "$NGINX_CONTAINER" nginx -t
nerdctl exec "$NGINX_CONTAINER" nginx -s reload
sleep 6

# --- Step 10: Validate HTTPS setup ---
echo "🔍 Validating HTTPS setup..."
if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME/health" | grep -q "200"; then
    echo "✅ HTTPS is working correctly!"
    echo "🌐 Your service is now available at: https://$DOMAIN_NAME"
else
    echo "⚠️  HTTPS setup completed but health check failed. Service might still be starting."
    echo "📋 Check with: curl -v https://$DOMAIN_NAME/health"
fi

# --- Step 11: Set up automatic certificate renewal ---
echo "⏰ Setting up automatic certificate renewal..."
# Create a renewal script
RENEWAL_SCRIPT="/etc/cron.daily/renew-ssl-certs"
sudo tee "$RENEWAL_SCRIPT" > /dev/null <<'EOF'
#!/bin/bash
certbot renew --non-interactive --config-dir /etc/container-infra/nginx/letsencrypt \
              --work-dir /etc/container-infra/nginx/letsencrypt/work \
              --logs-dir /etc/container-infra/nginx/letsencrypt/logs
if [ $? -eq 0 ]; then
    nerdctl exec nginx_proxy nginx -s reload
fi
EOF

sudo chmod +x "$RENEWAL_SCRIPT"

echo "🎉 HTTPS configuration complete!"
echo "🔐 SSL Certificate: $LETSENCRYPT_DIR/live/$DOMAIN_NAME/"
echo "📁 Configuration: $NGINX_CONF_FILE"
echo "🔄 Automatic renewal: $RENEWAL_SCRIPT"