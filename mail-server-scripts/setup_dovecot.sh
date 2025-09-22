#!/bin/bash
# Dovecot + SASL Setup Script (idempotent)
# Usage: ./setup_dovecot.sh <domain> path/to/.env
# Example: ./setup_dovecot.sh example.com ./mail.env

set -euo pipefail

# -------------------------
# Arguments
# -------------------------
DOMAIN="${1:-}"
ENV_FILE="${2:-}"

if [[ -z "$DOMAIN" || -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "Usage: $0 <domain> path/to/.env"
  exit 1
fi

# -------------------------
# Load environment (DB only)
# -------------------------
set -a
source "$ENV_FILE"
set +a

# Required DB vars
for var in DB_HOST DB_PORT DB_NAME DB_USER DB_PASS; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required env variable: $var"
    exit 1
  fi
done

# -------------------------
# Require root
# -------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# -------------------------
# Clean up any existing sockets that might cause conflicts
# -------------------------
echo "🧹 Cleaning up any existing Dovecot sockets..."
rm -f /var/run/dovecot/* 2>/dev/null || true
rm -f /var/spool/postfix/private/auth 2>/dev/null || true

# -------------------------
# Install Dovecot if missing
# -------------------------
if ! command -v dovecot >/dev/null 2>&1; then
  echo "📦 Installing Dovecot..."
  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-pgsql
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y dovecot dovecot-pgsql
  else
    echo "❌ Unsupported package manager. Install Dovecot manually."
    exit 1
  fi
else
  echo "✅ Dovecot already installed"
fi

# -------------------------
# Configure Dovecot
# -------------------------
DOVECOT_CONF_DIR="/etc/dovecot"
mkdir -p "$DOVECOT_CONF_DIR/conf.d"

# SSL config - check if certs exist, if not use self-signed
SSL_CERT="/etc/container-infra/nginx/letsencrypt/live/${DOMAIN}/fullchain.pem"
SSL_KEY="/etc/container-infra/nginx/letsencrypt/live/${DOMAIN}/privkey.pem"

if [[ ! -f "$SSL_CERT" || ! -f "$SSL_KEY" ]]; then
  echo "⚠️  SSL certificates not found, using self-signed"
  SSL_CERT="/etc/ssl/certs/dovecot.pem"
  SSL_KEY="/etc/ssl/private/dovecot.key"
  
  # Generate self-signed cert if needed
  if [[ ! -f "$SSL_CERT" ]]; then
    mkdir -p /etc/ssl/certs /etc/ssl/private
    openssl req -new -x509 -nodes -out "$SSL_CERT" -keyout "$SSL_KEY" \
      -subj "/CN=$DOMAIN" -days 365 2>/dev/null
  fi
fi

cat > "$DOVECOT_CONF_DIR/conf.d/10-ssl.conf" <<EOF
ssl = required
ssl_cert = <$SSL_CERT
ssl_key = <$SSL_KEY
ssl_min_protocol = TLSv1.2
EOF

# Mailbox location
cat > "$DOVECOT_CONF_DIR/conf.d/10-mail.conf" <<EOF
mail_location = maildir:/var/mail/vhosts/%d/%n/Maildir
namespace inbox {
  inbox = yes
}
EOF

# Authentication
cat > "$DOVECOT_CONF_DIR/conf.d/10-auth.conf" <<EOF
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-sql.conf.ext
EOF

cat > "$DOVECOT_CONF_DIR/conf.d/auth-sql.conf.ext" <<EOF
passdb {
  driver = sql
  args = $DOVECOT_CONF_DIR/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

cat > "$DOVECOT_CONF_DIR/dovecot-sql.conf.ext" <<EOF
driver = pgsql
connect = host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_USER password=$DB_PASS
default_pass_scheme = BLF-CRYPT
password_query = SELECT email as user, password FROM users WHERE email='%u';
EOF

# Postfix SASL integration - FIXED: Only one auth socket for Postfix
cat > "$DOVECOT_CONF_DIR/conf.d/10-master.conf" <<EOF
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}

service anvil {
  chroot =
}

service stats {
  chroot =
}
EOF

# -------------------------
# System user for mail storage
# -------------------------
if ! id -u vmail >/dev/null 2>&1; then
  echo "👤 Creating vmail user..."
  useradd -r -u 5000 -d /var/mail vmail
fi

mkdir -p /var/mail/vhosts
chown -R vmail:vmail /var/mail

# -------------------------
# Fix permissions and create necessary directories
# -------------------------
mkdir -p /var/run/dovecot
chown -R dovecot:dovecot /var/run/dovecot

# -------------------------
# Validate configuration
# -------------------------
echo "🔍 Validating Dovecot configuration..."
if ! dovecot -n 2>&1; then
  echo "❌ Dovecot configuration validation failed"
  exit 1
fi

# -------------------------
# Restart services
# -------------------------
echo "🔄 Restarting Dovecot..."
systemctl enable dovecot

# Stop Dovecot if it's running (even if failed)
systemctl stop dovecot 2>/dev/null || true

# Remove any stale sockets
rm -f /var/run/dovecot/* 2>/dev/null || true
rm -f /var/spool/postfix/private/auth 2>/dev/null || true

# Start Dovecot
if systemctl start dovecot; then
  echo "✅ Dovecot started successfully"
  sleep 2
  systemctl status dovecot --no-pager -l
else
  echo "❌ Failed to start Dovecot"
  journalctl -u dovecot -n 20 --no-pager
  exit 1
fi

echo "🎉 Dovecot + SASL configured successfully for $DOMAIN"