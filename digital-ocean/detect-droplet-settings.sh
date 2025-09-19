#!/bin/bash
# detect-original-settings.sh - Helper script to detect original droplet settings
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Detecting original settings...${NC}"

# Try to detect droplet ID from metadata service (if running on DigitalOcean)
DROPLET_ID=""
if curl -s --max-time 2 http://169.254.169.254/metadata/v1/id >/dev/null 2>&1; then
    DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)
    echo -e "${GREEN}Detected Droplet ID: $DROPLET_ID${NC}"
else
    echo -e "${YELLOW}Droplet ID: (not detected automatically)${NC}"
fi

# Try to detect original hostname from backups
ORIGINAL_NAME=""
if [[ -f "/etc/hostname.bak" ]]; then
    ORIGINAL_NAME=$(cat /etc/hostname.bak)
    echo -e "${GREEN}Detected original hostname from backup: $ORIGINAL_NAME${NC}"
elif [[ -f "/etc/hosts.bak" ]]; then
    ORIGINAL_NAME=$(grep "^127.0.1.1" /etc/hosts.bak | awk '{print $2}' | head -1)
    if [[ -n "$ORIGINAL_NAME" ]]; then
        echo -e "${GREEN}Detected original hostname from hosts backup: $ORIGINAL_NAME${NC}"
    fi
fi

# If no backup found, try to suggest based on common patterns
if [[ -z "$ORIGINAL_NAME" ]]; then
    CURRENT_HOSTNAME=$(hostname)
    if [[ "$CURRENT_HOSTNAME" =~ \. ]]; then
        # Current hostname is FQDN, extract the first part
        SUGGESTED_NAME=$(echo "$CURRENT_HOSTNAME" | cut -d'.' -f1)
        echo -e "${BLUE}Suggested hostname: $SUGGESTED_NAME${NC}"
        echo -e "${YELLOW}Note: This is a suggestion. Use the original DigitalOcean-assigned name if known.${NC}"
    else
        echo -e "${BLUE}Current hostname: $CURRENT_HOSTNAME (may already be original)${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}Usage examples:${NC}"

if [[ -n "$DROPLET_ID" ]] && [[ -n "$ORIGINAL_NAME" ]]; then
    echo -e "${GREEN}  # Cleanup using detected values${NC}"
    echo "  export DO_API_TOKEN=your_token"
    echo "  $0 $DROPLET_ID \"$ORIGINAL_NAME\" --cleanup"
    echo ""
fi

echo -e "${GREEN}  # Set PTR record${NC}"
echo "  export DO_API_TOKEN=your_token"
echo "  $0 <droplet-id> <fqdn>"
echo ""
echo -e "${GREEN}  # Cleanup PTR record${NC}"
echo "  export DO_API_TOKEN=your_token"
echo "  $0 <droplet-id> <original-hostname> --cleanup"
echo ""
echo -e "${GREEN}  # Show help${NC}"
echo "  $0 --help"