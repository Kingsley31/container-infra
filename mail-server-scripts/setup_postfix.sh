#!/bin/bash
# Postfix + PostgreSQL + SSL Configuration Script (idempotent)
# Usage: ./setup_postfix.sh <domain> /path/to/.env
# Example: ./setup_postfix.sh example.com ./db.env

set -euo pipefail

DOMAIN="${1:-}"
ENV_FILE="${2:-}"

if [[ -z "$DOMAIN" || -z "$ENV_FILE" ]]; then
  echo "Usage: $0 <domain> /path/to/.env"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Environment file not found: $ENV_FILE"
  exit 1
fi

# Load env vars from file
set -a
source "$ENV_FILE"
set +a

# Validate required vars
for var in DB_HOST DB_PORT DB_NAME DB_USER DB_PASS; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required variable: $var in $ENV_FILE"
    exit 1
  fi
done

# Require root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# Ensure Postfix is installed
if ! command -v postfix >/dev/null 2>&1; then
  echo "📦 Installing Postfix..."
  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y postfix postfix-pgsql
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y postfix postfix-pgsql
  else
    echo "❌ Unsupported package manager. Install Postfix manually."
    exit 1
  fi
else
  echo "✅ Postfix already installed"
fi

# Configure main.cf
echo "⚙️ Configuring Postfix (main.cf)..."
postconf -e "myhostname = mail.${DOMAIN}"
postconf -e "mydomain = ${DOMAIN}"
postconf -e "myorigin = /etc/mailname"
echo "$DOMAIN" > /etc/mailname

postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"

postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
postconf -e "relay_domains ="
postconf -e "home_mailbox = Maildir/"

# PostgreSQL integration
PGSQL_MAPS_DIR="/etc/postfix/pgsql"
mkdir -p "$PGSQL_MAPS_DIR"

cat > "$PGSQL_MAPS_DIR/virtual_mailbox_maps.cf" <<EOF
user = $DB_USER
password = $DB_PASS
hosts = $DB_HOST
port = $DB_PORT
dbname = $DB_NAME
query = SELECT maildir FROM users WHERE email='%s'
EOF

cat > "$PGSQL_MAPS_DIR/virtual_alias_maps.cf" <<EOF
user = $DB_USER
password = $DB_PASS
hosts = $DB_HOST
port = $DB_PORT
dbname = $DB_NAME
query = SELECT destination FROM aliases WHERE source='%s'
EOF

postconf -e "virtual_mailbox_domains = pgsql:$PGSQL_MAPS_DIR/virtual_mailbox_maps.cf"
postconf -e "virtual_mailbox_maps = pgsql:$PGSQL_MAPS_DIR/virtual_mailbox_maps.cf"
postconf -e "virtual_alias_maps = pgsql:$PGSQL_MAPS_DIR/virtual_alias_maps.cf"

# SSL (paths must exist already, script doesn’t generate them)
VOLUME_PATH="/etc/container-infra/nginx"
SSL_CERT="$VOLUME_PATH/letsencrypt/live/${DOMAIN}/fullchain.pem"
SSL_KEY="$VOLUME_PATH/letsencrypt/live/${DOMAIN}/privkey.pem"

postconf -e "smtpd_tls_cert_file = $SSL_CERT"
postconf -e "smtpd_tls_key_file = $SSL_KEY"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"

# Idempotent master.cf changes (submission + smtps)
MASTER_CF="/etc/postfix/master.cf"

add_service_if_missing() {
  local service="$1"
  local config="$2"

  if ! grep -q "^\s*${service}\s" "$MASTER_CF"; then
    echo "🔧 Adding $service service to master.cf..."
    echo -e "$config" >> "$MASTER_CF"
  else
    echo "✅ $service service already present"
  fi
}

add_service_if_missing "submission" "submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING"

add_service_if_missing "smtps" "smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING"

# Restart Postfix
systemctl restart postfix
echo "🎉 Postfix setup complete for $DOMAIN with PostgreSQL + SSL + ports 587/465"
