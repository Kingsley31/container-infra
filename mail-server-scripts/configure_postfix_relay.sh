#!/bin/bash
# Postfix SMTP Relay Configuration Script
# Usage: ./configure_postfix_relay.sh /path/to/env-file

set -euo pipefail

# -------------------------
# Arguments and Validation
# -------------------------
ENV_FILE="${1:-}"

if [[ -z "$ENV_FILE" ]]; then
    echo "❌ Usage: $0 /path/to/env-file"
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Environment file not found: $ENV_FILE"
    exit 1
fi

# -------------------------
# Load Environment Variables
# -------------------------
echo "📁 Loading environment variables from: $ENV_FILE"
set -a
source "$ENV_FILE"
set +a

# -------------------------
# Validate Required Variables
# -------------------------
REQUIRED_VARS=("SMTP_RELAY_HOST" "SMTP_RELAY_PORT" "SMTP_RELAY_USERNAME" "SMTP_RELAY_PASSWORD")

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ Missing required variable: $var"
        exit 1
    fi
done

# Set defaults for optional variables
SMTP_RELAY_TLS_LEVEL="${SMTP_RELAY_TLS_LEVEL:-encrypt}"
SMTP_RELAY_SASL_MECHANISM="${SMTP_RELAY_SASL_MECHANISM:-plain}"

# -------------------------
# Require Root
# -------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    echo "❌ Please run this script as root (use sudo)."
    exit 1
fi

# -------------------------
# Check Postfix Installation
# -------------------------
if ! command -v postfix >/dev/null 2>&1; then
    echo "📦 Installing Postfix..."
    if command -v apt >/dev/null 2>&1; then
        apt update
        DEBIAN_FRONTEND=noninteractive apt install -y postfix
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y postfix
    else
        echo "❌ Unsupported package manager. Install Postfix manually."
        exit 1
    fi
else
    echo "✅ Postfix already installed"
fi

# -------------------------
# Configure Postfix
# -------------------------
echo "⚙️ Configuring Postfix relay settings..."

# Backup original main.cf
if [[ ! -f /etc/postfix/main.cf.backup ]]; then
    cp /etc/postfix/main.cf /etc/postfix/main.cf.backup
    echo "✅ Backup created: /etc/postfix/main.cf.backup"
fi

# Configure relay settings
postconf -e "relayhost = [$SMTP_RELAY_HOST]:$SMTP_RELAY_PORT"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_sasl_mechanism_filter = $SMTP_RELAY_SASL_MECHANISM"
postconf -e "smtp_tls_security_level = $SMTP_RELAY_TLS_LEVEL"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# -------------------------
# Create Authentication File
# -------------------------
echo "🔐 Creating SMTP authentication file..."

# Create sasl_passwd file
cat > /etc/postfix/sasl_passwd <<EOF
[$SMTP_RELAY_HOST]:$SMTP_RELAY_PORT $SMTP_RELAY_USERNAME:$SMTP_RELAY_PASSWORD
EOF

# Secure the credentials file
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

# -------------------------
# Test Configuration
# -------------------------
echo "🔍 Testing Postfix configuration..."
if ! postfix check; then
    echo "❌ Postfix configuration test failed"
    exit 1
fi

# -------------------------
# Restart Postfix
# -------------------------
echo "🔄 Restarting Postfix..."
systemctl restart postfix

# -------------------------
# Verify Configuration
# -------------------------
echo "✅ Postfix relay configuration complete!"
echo "📋 Configuration summary:"
echo "   Relay Host:    $SMTP_RELAY_HOST:$SMTP_RELAY_PORT"
echo "   Username:      $SMTP_RELAY_USERNAME"
echo "   TLS Level:     $SMTP_RELAY_TLS_LEVEL"
echo "   SASL Mechanism: $SMTP_RELAY_SASL_MECHANISM"

# Test the configuration
echo "🔍 Testing relay configuration..."
if postconf -n | grep -q "relayhost.*$SMTP_RELAY_HOST"; then
    echo "✅ Relay host configured successfully"
else
    echo "❌ Relay host configuration failed"
    exit 1
fi

echo "🎉 Postfix SMTP relay configuration completed successfully!"
echo "💡 You can test with: swaks --to test@example.com --from your-user@your-domain.com --server localhost --port 587 -tls"