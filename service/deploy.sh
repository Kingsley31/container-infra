#!/bin/bash
set -euo pipefail

# -------------------------------
# Inputs
# -------------------------------
NGINX_BASE_DIR=$1      # e.g., /home/username/nginx
SERVICE_NAME=$2        # e.g., backend
IMAGE_NAME=$3          # e.g., ghcr.io/kingsley31/meter-bill-api
VERSION=$4             # e.g., 2025.09.12.011309
ENV_FILE=$5            # Absolute path to env file
shift 5

if [ -z "$NGINX_BASE_DIR" ] || [ -z "$SERVICE_NAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$VERSION" ] || [ -z "$ENV_FILE" ]; then
  echo "Usage: $0 <nginx_base_dir> <service_name> <image_name> <version> <env_file>"
  exit 1
fi

CONTAINER_NAME="${SERVICE_NAME}_${VERSION}"
IMAGE_TAG="${IMAGE_NAME}:${VERSION}"

# -------------------------------
# Deployment history files
# -------------------------------
HISTORY_DIR="$NGINX_BASE_DIR/deploy_history"
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
sudo nerdctl run -d \
  --name "$CONTAINER_NAME" \
  --network nginx_network \
  -p "$APP_PORT:$APP_PORT" \
  -e "PORT=$APP_PORT" \
  --env-file "$ENV_FILE" \
  "$IMAGE_TAG" \
  2>&1 | tee /tmp/deploy_debug.log

# -------------------------------
# Network readiness check
# -------------------------------
echo "⏳ Waiting for container $CONTAINER_NAME to be reachable from nginx_proxy..."
for i in {1..10}; do
  if sudo nerdctl exec nginx_proxy ping -c1 -W1 $CONTAINER_NAME &>/dev/null; then
    echo "✅ Container is reachable on nginx_network!"
    break
  else
    echo "⚠️ Container not reachable from nginx_proxy yet..."
    sleep 2
  fi
done

if ! sudo nerdctl exec nginx_proxy ping -c1 -W1 $CONTAINER_NAME &>/dev/null; then
  echo "❌ Container is not reachable from nginx_proxy after multiple attempts."
  sudo nerdctl stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  sudo nerdctl rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# -------------------------------
# Service health check
# -------------------------------
echo "⏳ Checking service health on localhost:$APP_PORT..."
success=false
for i in {1..10}; do
  if curl -s http://localhost:$APP_PORT/health | grep "ok" >/dev/null; then
    success=true
    echo "✅ Container is healthy!"
    break
  else
    echo "⚠️ Health endpoint not ready yet..."
    sleep 2
  fi
done

if [ "$success" != true ]; then
  echo "❌ Health check failed!"
  sudo nerdctl stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  sudo nerdctl rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# -------------------------------
# Update/create Nginx upstream
# -------------------------------
echo "🔀 Updating Nginx upstream block for $SERVICE_NAME..."
if [ ! -f "$NGINX_CONF" ]; then
  cat > "$NGINX_CONF" <<EOL
upstream ${SERVICE_NAME}_upstream {
    server ${CONTAINER_NAME}:$APP_PORT;
}
EOL
else
  if grep -q "upstream ${SERVICE_NAME}_upstream" "$NGINX_CONF"; then
    sed -i "/upstream ${SERVICE_NAME}_upstream {/,/}/c upstream ${SERVICE_NAME}_upstream {\n    server ${CONTAINER_NAME}:$APP_PORT;\n}" "$NGINX_CONF"
  else
    cat >> "$NGINX_CONF" <<EOL

upstream ${SERVICE_NAME}_upstream {
    server ${CONTAINER_NAME}:$APP_PORT;
}
EOL
  fi
fi

sudo nerdctl exec nginx_proxy nginx -s reload

# -------------------------------
# Stop old container
# -------------------------------
if [ -n "$OLD_CONTAINER" ] && [ "$OLD_CONTAINER" != "$CONTAINER_NAME" ]; then
  echo "🧹 Stopping old container $OLD_CONTAINER..."
  sudo nerdctl stop "$OLD_CONTAINER" >/dev/null 2>&1 || true
  sudo nerdctl rm "$OLD_CONTAINER" >/dev/null 2>&1 || true
fi

# -------------------------------
# Record deployment
# -------------------------------
echo "$VERSION $APP_PORT" > "$ACTIVE_FILE"
echo "$(date -Iseconds) $VERSION $APP_PORT" >> "$HISTORY_FILE"

echo "🎉 Deployment complete for $SERVICE_NAME version $VERSION on port $APP_PORT"
