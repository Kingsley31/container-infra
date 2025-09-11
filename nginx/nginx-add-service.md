# nginx-add-service

This script automates the process of adding a new service to Nginx with:

- Domain configuration
- SSL certificates (via Let's Encrypt / certbot)
- Default load balancing
- Automatic elevation to root

It is designed to work with an **Nginx container** managed by `nerdctl`.

---

## 🔑 Prerequisites

- A running `nginx` container mounted with:

  ```bash
  nerdctl run -d --name nginx_proxy \
  --network nginx_network \
  -p 80:80 -p 443:443 \
  -v /opt/nginx/nginx.conf:/etc/nginx/nginx.conf \
  -v /opt/nginx/conf.d:/etc/nginx/conf.d \
  -v /opt/nginx/letsencrypt:/etc/letsencrypt \
  -v /opt/nginx/html:/usr/share/nginx/html \
  nginx:alpine
  ```

- `certbot` installed (the script installs it automatically if missing).  
- Your user must be allowed to run the script with **passwordless sudo**.

---

## ⚡ Setup

1. **Copy the script** to your home directory (or another location):  

   ```bash
   nano ~/nginx-add-service.sh
   ```

   Paste the script contents (see below) and save.

2. **Make it executable**:  

   ```bash
   chmod +x ~/nginx-add-service.sh
   ```

3. **Get the absolute path**:  

   ```bash
   realpath ~/nginx-add-service.sh
   ```

   Example output:  

   ```bash
   /home/ubuntu/nginx-add-service.sh
   ```

4. **Edit sudoers**:  

   ```bash
   sudo visudo
   ```

   Add this line at the bottom (replace `ubuntu` with your username and path with your script’s path):  

   ```bash
   ubuntu ALL=(ALL) NOPASSWD: /home/ubuntu/nginx-add-service.sh
   ```

---

## 🚀 Usage

Run the script directly (no `sudo` needed):  

```bash
./nginx-add-service.sh <nginx_base_dir> <service_name> <service_port> [domain_name]
```

### Examples

- Default domain (creates `myservice.example.com`):  

  ```bash
  ./nginx-add-service.sh /opt/nginx myservice 8080
  ```

- Custom domain:  

  ```bash
  ./nginx-add-service.sh /opt/nginx myservice 8080 mydomain.com
  ```

- Root domain + `www`:  

  ```bash
  ./nginx-add-service.sh /opt/nginx myservice 8080 /
  ```

---

## ✅ What it does

1. Ensures config directories exist inside `<nginx_base_dir>`:
   - `/conf.d` for Nginx configs
   - `/letsencrypt` for certificates
   - `/html` for webroot challenges

2. Obtains/renews SSL certificates with certbot (non-interactive).  

3. Generates an Nginx config for the service:
   - HTTP (80) → redirect to HTTPS  
   - HTTPS (443) with valid SSL certs  
   - Load-balancing `upstream` block  

4. Reloads the `nginx_proxy` container:

   ```bash
   nerdctl exec nginx_proxy nginx -s reload
   ```

---

## 🔒 Security

- Only this script is passwordless (`NOPASSWD` in sudoers).  
- Other commands will still require your sudo password.  

---

## 🎉 Result

After running, your service will be available securely at:  

- `https://<domain_name>`  
- With automatic SSL setup and Nginx load balancing.

---

## 📜 Full Script

```bash
#!/bin/bash
set -euo pipefail

# Auto-elevate with sudo if not root
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# Usage examples:
# ./nginx-add-service.sh /opt/nginx myservice 8080
# ./nginx-add-service.sh /opt/nginx myservice 8080 mydomain.com
# ./nginx-add-service.sh /opt/nginx myservice 8080 /

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <nginx_base_dir> <service_name> <service_port> [domain_name]"
    echo "Examples:"
    echo "  $0 /opt/nginx myservice 8080             # default: myservice.example.com"
    echo "  $0 /opt/nginx myservice 8080 mydomain.com  # custom domain"
    echo "  $0 /opt/nginx myservice 8080 /          # uses example.com and www.example.com"
    exit 1
fi

NGINX_BASE_DIR=$1
SERVICE_NAME=$2
SERVICE_PORT=$3
DOMAIN_INPUT=${4:-""}
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

echo "Configuring service '$SERVICE_NAME' on port $SERVICE_PORT..."
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

# 3. Write Nginx config with SSL + load balancing
tee "$NGINX_CONF_FILE" > /dev/null <<EOF
upstream ${SERVICE_NAME}_upstream {
    server host.docker.internal:$SERVICE_PORT;
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

echo "Nginx config with SSL written to $NGINX_CONF_FILE"

# 4. Reload Nginx container
echo "Reloading Nginx container..."
nerdctl exec "$NGINX_CONTAINER" nginx -s reload

echo "✅ Service '$SERVICE_NAME' configured with SSL at $DOMAIN_NAME${DOMAIN_ALIAS:+, $DOMAIN_ALIAS} and load balancing enabled."
```
