#!/bin/bash

# DigitalOcean Droplet PTR Record Manager
# Sets or cleans up PTR records by renaming droplets
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${2}${1}${NC}"
}

# Function to display usage
usage() {
    echo "Usage: $0 <droplet-id> <fqdn> [--cleanup]"
    echo "  droplet-id: DigitalOcean droplet ID"
    echo "  fqdn: Fully Qualified Domain Name (e.g., server.example.com)"
    echo "  --cleanup: Optional flag to revert to original hostname"
    echo ""
    echo "Environment Variables:"
    echo "  DO_API_TOKEN: DigitalOcean API token (required)"
    echo "  ORIGINAL_HOSTNAME: Original hostname for cleanup (optional)"
    exit 1
}

# Check if required environment variable is set
if [[ -z "${DO_API_TOKEN:-}" ]]; then
    print_status "Error: DO_API_TOKEN environment variable is not set" "$RED"
    echo "Please set your DigitalOcean API token:"
    echo "  export DO_API_TOKEN=your_api_token_here"
    echo "Or run: DO_API_TOKEN=your_token $0 <droplet-id> <fqdn> [--cleanup]"
    exit 1
fi

# Parse arguments
CLEANUP_MODE=false
DROPLET_ID=""
FQDN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup)
            CLEANUP_MODE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$DROPLET_ID" ]]; then
                DROPLET_ID="$1"
            elif [[ -z "$FQDN" ]]; then
                FQDN="$1"
            else
                print_status "Error: Too many arguments" "$RED"
                usage
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$DROPLET_ID" ]] || [[ -z "$FQDN" ]]; then
    print_status "Error: Missing required arguments" "$RED"
    usage
fi

API_URL="https://api.digitalocean.com/v2"
MAX_RETRIES=30
RETRY_DELAY=10

# Validate droplet ID is numeric
if ! [[ "$DROPLET_ID" =~ ^[0-9]+$ ]]; then
    print_status "Error: Droplet ID must be numeric: $DROPLET_ID" "$RED"
    exit 1
fi

# In cleanup mode, FQDN is treated as the original hostname to revert to
if [[ "$CLEANUP_MODE" == true ]]; then
    TARGET_NAME="$FQDN"
    print_status "Cleanup mode: Reverting to original hostname: $TARGET_NAME" "$YELLOW"
else
    # Validate FQDN format (basic validation) only in set mode
    if ! [[ "$FQDN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_status "Error: Invalid FQDN format: $FQDN" "$RED"
        echo "Please provide a valid FQDN (e.g., server.example.com)"
        exit 1
    fi
    TARGET_NAME="$FQDN"
fi

# Function to make API requests
do_api_request() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    
    local curl_cmd=("curl" -s -X "$method" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        "$API_URL/$endpoint")
    
    if [[ -n "$data" ]]; then
        curl_cmd+=(-d "$data")
    fi
    
    "${curl_cmd[@]}"
}

# Function to check if droplet exists
check_droplet_exists() {
    local response
    response=$(do_api_request "droplets/$DROPLET_ID")
    
    if echo "$response" | grep -q '"id"'; then
        return 0
    else
        return 1
    fi
}

# Function to get current droplet name
get_droplet_name() {
    do_api_request "droplets/$DROPLET_ID" | grep -o '"name":"[^"]*' | cut -d'"' -f4
}

# Function to rename droplet (which sets PTR record)
rename_droplet() {
    local new_name="$1"
    local data="{\"name\":\"$new_name\"}"
    local response
    response=$(do_api_request "droplets/$DROPLET_ID" "PUT" "$data")
    
    if echo "$response" | grep -q '"id"'; then
        return 0
    else
        return 1
    fi
}

# Function to set local hostname
set_local_hostname() {
    local hostname="$1"
    
    print_status "Setting local hostname to: $hostname" "$BLUE"
    
    # Backup current configuration
    if [[ ! -f "/etc/hostname.bak" ]] && [[ -f "/etc/hostname" ]]; then
        cp /etc/hostname /etc/hostname.bak
        print_status "✓ Backed up /etc/hostname" "$GREEN"
    fi
    
    # Set hostname using hostnamectl (systemd)
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$hostname"
        print_status "✓ Hostname set using hostnamectl" "$GREEN"
    else
        # Fallback to traditional method
        echo "$hostname" | tee /etc/hostname >/dev/null
        hostname "$hostname"
        print_status "✓ Hostname set using traditional method" "$GREEN"
    fi
    
    # Update /etc/hosts if needed
    if ! grep -q "^127.0.1.1.*$hostname" /etc/hosts; then
        # Backup hosts file if not already backed up
        if [[ ! -f "/etc/hosts.bak" ]] && [[ -f "/etc/hosts" ]]; then
            cp /etc/hosts /etc/hosts.bak
            print_status "✓ Backed up /etc/hosts" "$GREEN"
        fi
        
        # Remove any existing 127.0.1.1 entry
        sed -i '/^127.0.1.1/d' /etc/hosts
        # Add new entry
        echo "127.0.1.1 $hostname" | tee -a /etc/hosts >/dev/null
        print_status "✓ Updated /etc/hosts" "$GREEN"
    fi
}

# Function to verify droplet rename with retries
verify_droplet_rename() {
    local expected_name="$1"
    local attempt=1
    
    print_status "Verifying droplet rename (max $MAX_RETRIES attempts, ${RETRY_DELAY}s intervals)..." "$BLUE"
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        print_status "Attempt $attempt/$MAX_RETRIES: Checking droplet name..." "$YELLOW"
        
        local current_name
        if current_name=$(get_droplet_name 2>/dev/null); then
            if [[ "$current_name" == "$expected_name" ]]; then
                print_status "✓ Success! Droplet name confirmed: $current_name" "$GREEN"
                return 0
            else
                print_status "Current name: $current_name (waiting for: $expected_name)" "$YELLOW"
            fi
        else
            print_status "Failed to get droplet name (attempt $attempt)" "$YELLOW"
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            print_status "Waiting ${RETRY_DELAY} seconds before next check..." "$YELLOW"
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done
    
    print_status "✗ Failed to verify droplet rename after $MAX_RETRIES attempts" "$RED"
    return 1
}

# Main execution
if [[ "$CLEANUP_MODE" == true ]]; then
    print_status "Starting cleanup process for droplet $DROPLET_ID..." "$YELLOW"
else
    print_status "Starting PTR record configuration for droplet $DROPLET_ID..." "$YELLOW"
fi

# Check if droplet exists
print_status "Checking if droplet $DROPLET_ID exists..." "$YELLOW"
if ! check_droplet_exists; then
    print_status "Error: Droplet $DROPLET_ID not found or inaccessible" "$RED"
    if [[ "$CLEANUP_MODE" == true ]]; then
        print_status "Continuing with local hostname cleanup only..." "$YELLOW"
    else
        exit 1
    fi
fi

# Get current droplet name if available
if check_droplet_exists; then
    current_name=$(get_droplet_name)
    print_status "Current droplet name: $current_name" "$GREEN"
fi

# Set local hostname
print_status "Updating local machine hostname..." "$BLUE"
set_local_hostname "$TARGET_NAME"

# Rename droplet to set/cleanup PTR record
if check_droplet_exists; then
    print_status "Renaming droplet to: $TARGET_NAME" "$YELLOW"
    if rename_droplet "$TARGET_NAME"; then
        print_status "✓ Rename request accepted by DigitalOcean API" "$GREEN"
        
        # Verify the droplet was actually renamed
        if verify_droplet_rename "$TARGET_NAME"; then
            print_status "✓ Droplet rename confirmed successfully!" "$GREEN"
        else
            print_status "⚠ Warning: Unable to confirm droplet rename, but request was accepted" "$YELLOW"
        fi
    else
        print_status "✗ Failed to rename droplet via API" "$RED"
        if [[ "$CLEANUP_MODE" == true ]]; then
            print_status "Continuing with local hostname cleanup..." "$YELLOW"
        else
            exit 1
        fi
    fi
fi

# Final status message
if [[ "$CLEANUP_MODE" == true ]]; then
    print_status "Cleanup completed successfully!" "$GREEN"
    print_status "Droplet and local hostname reverted to: $TARGET_NAME" "$GREEN"
    print_status "Backup files preserved at: /etc/hostname.bak and /etc/hosts.bak" "$YELLOW"
else
    print_status "Operation completed successfully!" "$GREEN"
    print_status "Local hostname has been set to: $(hostname)" "$GREEN"
    print_status "Droplet PTR record should now point to: $TARGET_NAME" "$GREEN"
    print_status "Note: DNS changes may take additional time to propagate" "$YELLOW"
fi