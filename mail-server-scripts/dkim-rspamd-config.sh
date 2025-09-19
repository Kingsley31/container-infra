#!/bin/bash
# DKIM Setup Script with Rspamd + DigitalOcean DNS Integration
# Usage: sudo ./dkim-rspamd-config.sh <domain> <vps_ip> <dns_script_path>
# Example: sudo ./dkim-rspamd-config.sh example.com 203.0.113.45 ./create_dkim_record.sh

set -euo pipefail

# -------------------------
# Require root
# -------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)."
  exit 1
fi

# -------------------------
# Arguments
# -------------------------
DOMAIN="${1:-}"
IP="${2:-}"
DNS_SCRIPT="${3:-}"

if [[ -z "$DOMAIN" || -z "$IP" || -z "$DNS_SCRIPT" ]]; then
  echo "Usage: $0 <domain> <vps_ip> <dns_script_path>"
  exit 1
fi

if [ ! -x "$DNS_SCRIPT" ]; then
  echo "❌ DNS script not found or not executable: $DNS_SCRIPT"
  exit 1
fi

# -------------------------
# Check DO_API_TOKEN
# -------------------------
if [ -z "${DO_API_TOKEN:-}" ]; then
  echo "❌ DO_API_TOKEN environment variable is not set"
  exit 1
fi

# -------------------------
# Ensure rspamd is installed
# -------------------------
if ! command -v rspamadm >/dev/null 2>&1; then
  echo "📦 Installing Rspamd..."
  if command -v apt >/dev/null 2>&1; then
    apt update
    apt install -y rspamd
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y rspamd
  else
    echo "❌ Unsupported package manager. Install Rspamd manually."
    exit 1
  fi
else
  echo "✅ Rspamd already installed"
fi

# -------------------------
# Generate DKIM keys
# -------------------------
SELECTOR="mail"
KEY_DIR="/var/lib/rspamd/dkim"
KEY_FILE="$KEY_DIR/${DOMAIN}.${SELECTOR}.key"

echo "🔑 Generating DKIM key for $DOMAIN (selector: $SELECTOR)..."
mkdir -p "$KEY_DIR"
rspamadm dkim_keygen -b 2048 -s "$SELECTOR" -d "$DOMAIN" > /tmp/dkim.out

# Extract private key
PRIVATE_KEY=$(grep -A100 "PRIVATE KEY" /tmp/dkim.out)
echo "$PRIVATE_KEY" > "$KEY_FILE"
chown _rspamd:_rspamd "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Extract public record
PUBLIC_RECORD=$(grep -A100 "v=DKIM1" /tmp/dkim.out | tr -d '\n' | sed 's/.*v=DKIM1/v=DKIM1/')
DNS_NAME="${SELECTOR}._domainkey"

echo "✅ DKIM private key stored at $KEY_FILE"
echo "🔎 DKIM public record extracted"

# -------------------------
# Configure rspamd
# -------------------------
CONF_FILE="/etc/rspamd/local.d/dkim_signing.conf"
echo "⚙️ Configuring Rspamd DKIM signing..."
mkdir -p /etc/rspamd/local.d
cat > "$CONF_FILE" <<EOF
domain {
  $DOMAIN {
    path = "$KEY_FILE";
    selector = "$SELECTOR";
  }
}
EOF

systemctl restart rspamd
echo "✅ Rspamd configured and restarted"

# -------------------------
# Call external DNS script
# -------------------------
echo "🌐 Creating DKIM DNS record with $DNS_SCRIPT..."
"$DNS_SCRIPT" "$DOMAIN" "$IP" "$DNS_NAME" "$PUBLIC_RECORD"

echo "🎉 DKIM setup complete for $DOMAIN"
