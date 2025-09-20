#!/bin/bash
# UFW Email Server Firewall Setup
# Opens only the essential ports: 25, 587, 465, 143, 993
# Usage: sudo ./setup_ufw.sh

set -euo pipefail

# Require root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# Install UFW if missing
if ! command -v ufw >/dev/null 2>&1; then
  echo "📦 Installing UFW..."
  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y ufw
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ufw
  else
    echo "❌ Unsupported package manager. Install UFW manually."
    exit 1
  fi
else
  echo "✅ UFW already installed"
fi

echo "⚙️ Configuring UFW for email services..."

# Allow SSH to avoid locking yourself out
ufw allow OpenSSH || ufw allow 22

# SMTP (MTA)
ufw allow 25    # SMTP relay
ufw allow 587   # Submission
ufw allow 465   # SMTPS

# IMAP (Dovecot)
ufw allow 143   # IMAP
ufw allow 993   # IMAPS

# Enable UFW if not enabled
if ufw status | grep -q "inactive"; then
  echo "🚀 Enabling UFW..."
  ufw --force enable
else
  echo "✅ UFW already enabled"
fi

echo "🎉 UFW configured. Allowed ports:"
ufw status numbered
