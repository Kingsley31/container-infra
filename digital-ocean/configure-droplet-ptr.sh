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

print_status() {
    echo -e "${2}${1}${NC}"
}

usage() {
    echo "Usage: $0 <droplet-id> <fqdn> [--cleanup]"
    exit 1
}

if [[ -z "${DO_API_TOKEN:-}" ]]; then
    print_status "Error: DO_API_TOKEN environment variable is not set" "$RED"
    exit 1
fi

CLEANUP_MODE=false
DROPLET_ID=""
FQDN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup) CLEANUP_MODE=true; shift ;;
        --help|-h) usage ;;
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

if [[ -z "$DROPLET_ID" ]] || [[ -z "$FQDN" ]]; then
    usage
fi

API_URL="https://api.digitalocean.com/v2"
MAX_RETRIES=30
RETRY_DELAY=10

if ! [[ "$DROPLET_ID" =~ ^[0-9]+$ ]]; then
    print_status "Error: Droplet ID must be numeric" "$RED"
    exit 1
fi

if [[ "$CLEANUP_MODE" == true ]]; then
    TARGET_NAME="$FQDN"
else
    if ! [[ "$FQDN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_status "Error: Invalid FQDN format: $FQDN" "$RED"
        exit 1
    fi
    TARGET_NAME="$FQDN"
fi

##############################################
# Core API request helper
##############################################
do_api_request() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="${3:-}"

    local response http_status response_body

    if [[ -n "$data" ]]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $DO_API_TOKEN" \
            -d "$data" \
            "$API_URL/$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $DO_API_TOKEN" \
            "$API_URL/$endpoint")
    fi

    http_status=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')

    echo "$http_status"
    echo "$response_body"
}

##############################################
# Droplet helpers
##############################################
check_droplet_exists() {
    local response
    response=$(do_api_request "droplets/$DROPLET_ID")
    local http_status=$(echo "$response" | head -n1)
    local body=$(echo "$response" | tail -n +2)

    if [ "$http_status" -eq 200 ] && echo "$body" | grep -q '"id"'; then
        return 0
    else
        print_status "Droplet check failed. Status: $http_status" "$RED"
        print_status "Response: $body" "$RED"
        return 1
    fi
}

get_droplet_name() {
    local response
    response=$(do_api_request "droplets/$DROPLET_ID")
    local http_status=$(echo "$response" | head -n1)
    local body=$(echo "$response" | tail -n +2)

    if [ "$http_status" -eq 200 ]; then
        echo "$body" | grep -o '"name":"[^"]*' | cut -d'"' -f4
    else
        print_status "Failed to get droplet name. Status: $http_status" "$RED"
        print_status "Response: $body" "$RED"
        return 1
    fi
}

rename_droplet() {
    local new_name="$1"
    local data="{\"name\":\"$new_name\"}"

    print_status "Sending rename request to DigitalOcean API..." "$BLUE"
    print_status "Request data: $data" "$YELLOW"

    local response
    response=$(do_api_request "droplets/$DROPLET_ID" "PUT" "$data")
    local http_status=$(echo "$response" | head -n1)
    local body=$(echo "$response" | tail -n +2)

    print_status "API response status: $http_status" "$BLUE"
    print_status "API response body: $body" "$YELLOW"

    if [ "$http_status" -eq 200 ]; then
        print_status "✓ Rename request successful" "$GREEN"
        return 0
    else
        print_status "✗ Rename request failed with HTTP status: $http_status" "$RED"
        local error_message
        error_message=$(echo "$body" | grep -o '"message":"[^"]*' | cut -d'"' -f4 || echo "Unknown error")
        print_status "Error message: $error_message" "$RED"
        return 1
    fi
}

verify_droplet_rename() {
    local expected_name="$1"
    local attempt=1

    print_status "Verifying droplet rename (max $MAX_RETRIES attempts)..." "$BLUE"

    while [[ $attempt -le $MAX_RETRIES ]]; do
        local current_name
        if current_name=$(get_droplet_name 2>/dev/null); then
            if [[ "$current_name" == "$expected_name" ]]; then
                print_status "✓ Success! Droplet name confirmed: $current_name" "$GREEN"
                return 0
            else
                print_status "Current name: $current_name (waiting for: $expected_name)" "$YELLOW"
            fi
        fi
        sleep $RETRY_DELAY
        ((attempt++))
    done
    return 1
}

##############################################
# Local hostname
##############################################
set_local_hostname() {
    local hostname="$1"
    print_status "Setting local hostname to: $hostname" "$BLUE"
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$hostname"
    else
        echo "$hostname" > /etc/hostname
        hostname "$hostname"
    fi
    print_status "✓ Hostname set" "$GREEN"
}

##############################################
# Main
##############################################
if [[ "$CLEANUP_MODE" == true ]]; then
    print_status "Starting cleanup for droplet $DROPLET_ID..." "$YELLOW"
else
    print_status "Starting PTR record configuration for droplet $DROPLET_ID..." "$YELLOW"
fi

if ! check_droplet_exists; then
    print_status "Error: Droplet $DROPLET_ID not found or inaccessible" "$RED"
    exit 1
fi

current_name=$(get_droplet_name)
print_status "Current droplet name: $current_name" "$GREEN"

set_local_hostname "$TARGET_NAME"

print_status "Renaming droplet to: $TARGET_NAME" "$YELLOW"
if rename_droplet "$TARGET_NAME"; then
    verify_droplet_rename "$TARGET_NAME" || print_status "⚠ Could not verify rename yet" "$YELLOW"
else
    exit 1
fi

print_status "Done! PTR record should now point to: $TARGET_NAME" "$GREEN"
