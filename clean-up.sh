#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -e

echo "🧹 Starting cleanup of container infrastructure..."

# 1. Stop and remove all containers
echo "🗑️  Removing all containers..."
sudo nerdctl rm -f $(sudo nerdctl ps -aq) 2>/dev/null || true

# 2. Remove custom networks (keep default ones)
echo "🌐 Removing custom networks..."
for network in $(sudo nerdctl network ls -q); do
    if [ "$network" != "bridge" ] && [ "$network" != "host" ] && [ "$network" != "none" ]; then
        sudo nerdctl network rm "$network" 2>/dev/null || true
    fi
done

# 3. Remove configuration directories
echo "📁 Removing configuration directories..."
sudo rm -rf /etc/container-infra
sudo rm -rf /var/lib/container-infra

# 4. Clean up nerdctl runtime data
echo "🔧 Cleaning up nerdctl runtime data..."
sudo rm -rf /var/lib/nerdctl/*

echo "✅ Cleanup complete! Containers, networks, and configs removed."
echo "ℹ️  Container images were preserved for future use."