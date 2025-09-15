#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

set -euo pipefail

# -------------------------------
# Inputs
# -------------------------------
NGINX_BASE_DIR="/etc/container-infra/nginx"     # e.g., /home/username/nginx
SERVICE_NAME=$1        # e.g., backend
IMAGE_NAME=$2          # e.g., ghcr.io/kingsley31/meter-bill-api
VERSION=$3             # e.g., 2025.09.12.011309
ENV_FILE=$4            # Absolute path to env file
shift 4

# Optional health check path parameter
HEALTH_CHECK_PATH=${1:-"/health"}

if [ -z "$SERVICE_NAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$VERSION" ] || [ -z "$ENV_FILE" ]; then
  echo "Usage: $0 <service_name> <image_name> <version> <env_file> [health_check_path]"
  echo "  health_check_path: Optional path for health checks (default: /health)"
  exit 1
fi

CONTAINER_NAME="${SERVICE_NAME}_${VERSION}"
IMAGE_TAG="${IMAGE_NAME}:${VERSION}"

# -------------------------------
# Deployment history files
# -------------------------------
HISTORY_DIR="/var/lib/container-infra/deploy_history"
mkdir -p "$HISTORY_DIR"

ACTIVE_FILE="$HISTORY_DIR/${SERVICE_NAME}_active_version"
HISTORY_FILE="$HISTORY_DIR/${SERVICE_NAME}_history"

touch "$ACTIVE_FILE" "$HISTORY_FILE"

# -------------------------------
# Paths
# -------------------------------
mkdir -p "$NGINX_BASE_DIR/conf.d"
NGINX_CONF="$NGINX_BASE_DIR/conf.d/${SERVICE_NAME}.conf"

# -------------------------------
# Find a free port
# -------------------------------
find_free_port() {
  for PORT in $(seq 3000 5100); do
    if ! ss -ltn | awk '{print $4}' | grep -q ":$PORT$"; then
      echo $PORT
      return
    fi
  done
  echo "❌ No free ports available!" >&2
  exit 1
}

APP_PORT=$(find_free_port)
echo "🎯 Assigned port $APP_PORT for $CONTAINER_NAME"

# -------------------------------
# Stop previous version
# -------------------------------
if [ -s "$ACTIVE_FILE" ]; then
  OLD_LINE=$(cat "$ACTIVE_FILE")
  OLD_VERSION=$(echo $OLD_LINE | awk '{print $1}')
  OLD_PORT=$(echo $OLD_LINE | awk '{print $2}')
  OLD_CONTAINER="${SERVICE_NAME}_${OLD_VERSION}"
else
  OLD_VERSION=""
  OLD_PORT=""
  OLD_CONTAINER=""
fi

echo "📌 Current active container: ${OLD_CONTAINER:-none} on port ${OLD_PORT:-N/A}"

# -------------------------------
# Run new container
# -------------------------------
echo "🚀 Starting container $CONTAINER_NAME on port $APP_PORT..."
if [ ! -f "$ENV_FILE" ] || [ ! -r "$ENV_FILE" ]; then
  echo "❌ Env file '$ENV_FILE' does not exist or is not readable"
  exit 1
fi
# Run command and capture errors
nerdctl run -d \
  --name "$CONTAINER_NAME" \
  --network host \
  --restart always \
  -p "$APP_PORT:$APP_PORT" \
  -e "PORT=$APP_PORT" \
  --env-file "$ENV_FILE" \
  "$IMAGE_TAG" \
  2>&1 | tee /tmp/deploy_debug.log

# -------------------------------
# Service health check
# -------------------------------
echo "⏳ Waiting for container $CONTAINER_NAME to be reachable on port $APP_PORT..."
echo "🔍 Using health check path: $HEALTH_CHECK_PATH"
success=false

for i in {1..10}; do
  # Check if the port is open and service is responding
  if curl -sf --connect-timeout 2 "http://127.0.0.1:$APP_PORT$HEALTH_CHECK_PATH" >/dev/null; then
    success=true
    echo "✅ Container is reachable and healthy!"
    break
  else
    echo "⚠️ Service not reachable on port $APP_PORT$HEALTH_CHECK_PATH yet (attempt $i/10)..."
    sleep 2
  fi
done

if [ "$success" != true ]; then
  echo "❌ Service failed to become reachable on port $APP_PORT$HEALTH_CHECK_PATH!"
  echo "📋 Checking container status..."
  nerdctl logs "$CONTAINER_NAME" | tail -20
  
  # Try base URL as fallback if health check failed
  echo "🔄 Trying base URL as fallback..."
  if curl -sf --connect-timeout 2 "http://127.0.0.1:$APP_PORT/" >/dev/null; then
    echo "✅ Container is reachable at base URL (health check path may be different)"
    success=true
  else
    echo "❌ Container also unreachable at base URL"
    nerdctl stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    nerdctl rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 1
  fi
fi

# -------------------------------
# Update/create Nginx upstream
# -------------------------------
echo "🔀 Updating Nginx upstream block for $SERVICE_NAME..."
if [ ! -f "$NGINX_CONF" ]; then
  cat > "$NGINX_CONF" <<EOL
upstream ${SERVICE_NAME}_upstream {
    server 127.0.0.1:$APP_PORT;
}
EOL
else
  if grep -q "upstream ${SERVICE_NAME}_upstream" "$NGINX_CONF"; then
    sed -i "/upstream ${SERVICE_NAME}_upstream {/,/}/c upstream ${SERVICE_NAME}_upstream {\n    server 127.0.0.1:$APP_PORT;\n}" "$NGINX_CONF"
  else
    cat >> "$NGINX_CONF" <<EOL

upstream ${SERVICE_NAME}_upstream {
    server 127.0.0.1:$APP_PORT;
}
EOL
  fi
fi

nerdctl exec nginx_proxy nginx -s reload

# -------------------------------
# Stop old container
# -------------------------------
if [ -n "$OLD_CONTAINER" ] && [ "$OLD_CONTAINER" != "$CONTAINER_NAME" ]; then
  echo "🧹 Stopping old container $OLD_CONTAINER..."
  nerdctl stop "$OLD_CONTAINER" >/dev/null 2>&1 || true
  nerdctl rm "$OLD_CONTAINER" >/dev/null 2>&1 || true
fi

# -------------------------------
# Record deployment
# -------------------------------
echo "$VERSION $APP_PORT" > "$ACTIVE_FILE"
echo "$(date -Iseconds) $VERSION $APP_PORT" >> "$HISTORY_FILE"

echo "🎉 Deployment complete for $SERVICE_NAME version $VERSION on port $APP_PORT"
echo "📊 Health check path: $HEALTH_CHECK_PATH"