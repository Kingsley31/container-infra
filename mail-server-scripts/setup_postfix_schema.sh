#!/bin/bash
# Postfix PostgreSQL Schema Setup Script (idempotent)
# Usage: ./setup_postfix_schema.sh /path/to/db.env
# Example: ./setup_postfix_schema.sh ./maildb.env

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script as root (use sudo)."
  exit 1
fi
# -------------------------
# Require .env file
# -------------------------
ENV_FILE="${1:-}"
if [[ -z "$ENV_FILE" ]]; then
  echo "Usage: $0 /path/to/db.env"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ .env file not found: $ENV_FILE"
  exit 1
fi

# Load environment variables from .env file
set -o allexport
source "$ENV_FILE"
set +o allexport

# -------------------------
# Validate variables
# -------------------------
: "${DB_HOST:?DB_HOST must be set in $ENV_FILE}"
: "${DB_PORT:?DB_PORT must be set in $ENV_FILE}"
: "${DB_NAME:?DB_NAME must be set in $ENV_FILE}"
: "${DB_USER:?DB_USER must be set in $ENV_FILE}"
: "${DB_PASS:?DB_PASS must be set in $ENV_FILE}"

# -------------------------
# Ensure psql client is installed
# -------------------------
if ! command -v psql >/dev/null 2>&1; then
  echo "📦 Installing PostgreSQL client..."
  if command -v apt >/dev/null 2>&1; then
    apt update
    apt install -y postgresql-client
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y postgresql
  elif command -v yum >/dev/null 2>&1; then
    yum install -y postgresql
  else
    echo "❌ Could not detect package manager. Install PostgreSQL client manually."
    exit 1
  fi
else
  echo "✅ psql client already installed"
fi

# -------------------------
# Run schema setup
# -------------------------
export PGPASSWORD="$DB_PASS"

echo "⚙️ Setting up Postfix schema in $DB_NAME on $DB_HOST:$DB_PORT ..."

psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<'EOF'
-- Domains table
CREATE TABLE IF NOT EXISTS domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    domain_id INT REFERENCES domains(id) ON DELETE CASCADE,
    maildir VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Aliases table
CREATE TABLE IF NOT EXISTS aliases (
    id SERIAL PRIMARY KEY,
    source VARCHAR(255) UNIQUE NOT NULL,
    destination VARCHAR(255) NOT NULL,
    domain_id INT REFERENCES domains(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_aliases_source ON aliases(source);
EOF

echo "✅ Schema setup complete (domains, users, aliases)."
