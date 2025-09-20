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

# SSL config
SSL_CERT="/etc/container-infra/nginx/letsencrypt/live/${DOMAIN}/fullchain.pem"
SSL_KEY="/etc/container-infra/nginx/letsencrypt/live/${DOMAIN}/privkey.pem"

cat > "$DOVECOT_CONF_DIR/conf.d/10-ssl.conf" <<EOF
ssl = required
ssl_cert = <$SSL_CERT
ssl_key = <$SSL_KEY
EOF

# Mailbox location
cat > "$DOVECOT_CONF_DIR/conf.d/10-mail.conf" <<EOF
mail_location = maildir:/var/mail/vhosts/%d/%n
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

# Postfix SASL integration
cat > "$DOVECOT_CONF_DIR/conf.d/10-master.conf" <<EOF
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  unix_listener /var/run/dovecot/auth-userdb {
    mode = 0600
    user = root
    group = root
  }
}
EOF

# -------------------------
# System user for mail storage
# -------------------------
if ! id -u vmail >/dev/null 2>&1; then
  echo "👤 Creating vmail user..."
  useradd -r -u 5000 vmail
fi

mkdir -p /var/mail/vhosts
chown -R vmail:vmail /var/mail

# -------------------------
# Restart services
# -------------------------
systemctl enable dovecot
systemctl restart dovecot

echo "🎉 Dovecot + SASL configured successfully for $DOMAIN"
