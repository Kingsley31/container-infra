#!/bin/bash
# Secure script to login to GitHub Container Registry with nerdctl
# Usage: ./ghcr-login.sh <github-username>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <github-username>"
  exit 1
fi

USERNAME=$1

# Prompt securely for token (input hidden)
read -s -p "Enter GitHub Personal Access Token: " TOKEN
echo ""

# Login with nerdctl
echo "$TOKEN" | nerdctl login ghcr.io -u "$USERNAME" --password-stdin
