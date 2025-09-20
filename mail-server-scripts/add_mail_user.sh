#!/bin/bash
# Add a mail user (idempotent) to Postfix + PostgreSQL
# Usage: ./add_mail_user.sh <email> <password> <path-to-env-file>

set -euo pipefail

# Require root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi

# Check arguments
if [ $# -ne 3 ]; then
  echo "Usage: $0 <email> <password> <path-to-env-file>"
  exit 1
fi

EMAIL="$1"
PASSWORD="$2"  # Don't quote here - let the caller handle quoting
ENV_FILE="$3"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Environment file $ENV_FILE not found."
  exit 1
fi

# Load DB connection vars
set -a
source "$ENV_FILE"
set +a

# Validate required variables
: "${DB_NAME:?Missing DB_NAME in $ENV_FILE}"
: "${DB_USER:?Missing DB_USER in $ENV_FILE}"
: "${DB_PASS:?Missing DB_PASS in $ENV_FILE}"
: "${DB_HOST:?Missing DB_HOST in $ENV_FILE}"
: "${DB_PORT:?Missing DB_PORT in $ENV_FILE}"

# Export password for non-interactive psql
export PGPASSWORD="$DB_PASS"

# Check/install dependencies
if ! command -v psql &>/dev/null; then
  echo "📦 Installing PostgreSQL client..."
  apt-get update -y
  apt-get install -y postgresql-client
fi

if ! command -v doveadm &>/dev/null; then
  echo "📦 Installing Dovecot tools..."
  apt-get update -y
  apt-get install -y dovecot-core dovecot-pop3d dovecot-imapd
fi

# Hash password with Dovecot - use single quotes to prevent expansion
HASHED_PASS=$(doveadm pw -s BLF-CRYPT -p "$PASSWORD")

# Extract domain and local part
DOMAIN="${EMAIL#*@}"
LOCALPART="${EMAIL%@*}"
MAILDIR="$DOMAIN/$LOCALPART/"

# Ensure domain exists
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
"INSERT INTO domains (name)
 VALUES ('$DOMAIN')
 ON CONFLICT (name) DO NOTHING;"

# Fetch domain ID (plain output)
DOMAIN_ID=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A \
  -c "SELECT id FROM domains WHERE name='$DOMAIN';")

# Insert user (idempotent) - use proper quoting for SQL
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO users (email, password, domain_id, maildir)
VALUES ('$EMAIL', '$HASHED_PASS', $DOMAIN_ID, '$MAILDIR')
ON CONFLICT (email) DO NOTHING;
SQL

# Insert self-alias (idempotent)
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO aliases (source, destination, domain_id)
VALUES ('$EMAIL', '$EMAIL', $DOMAIN_ID)
ON CONFLICT (source) DO NOTHING;
SQL

echo "✅ Mail user $EMAIL created successfully (domain_id=$DOMAIN_ID, maildir=$MAILDIR)"