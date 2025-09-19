#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path-to-env-file>"
  exit 1
fi

ENV_FILE=$1

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ File not found: $ENV_FILE"
  exit 1
fi

# Load variables from file
echo "📂 Loading environment variables from $ENV_FILE"
while IFS='=' read -r key value; do
  # Skip empty lines and comments
  if [[ -z "$key" || "$key" =~ ^# ]]; then
    continue
  fi

  # Remove surrounding quotes from value
  value=$(echo "$value" | sed -e 's/^["'\'']//;s/["'\'']$//')

  # Export variable
  export "$key=$value"
  echo "✅ Exported $key"
done < "$ENV_FILE"

echo "🎉 All environment variables loaded."
