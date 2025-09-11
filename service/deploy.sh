#!/bin/bash
set -e

# -------------------------------
# Inputs
# -------------------------------
SERVICE_NAME=$1     # e.g., myapp
IMAGE_NAME=$2       # e.g., myapp
VERSION=$3          # e.g., v1.2.3

if [ -z "$SERVICE_NAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$VERSION" ]; then
  echo "Usage: $0 <service_name> <image_name> <version> [ENV_VARS...]"
  exit 1
fi

CONTAINER_NAME="${SERVICE_NAME}_${VERSION}"
IMAGE_TAG="${IMAGE_NAME}:${VERSION}"

# Capture optional env vars (from 4th argument onwards)
ENV_VARS=("${@:4}")

# -------------------------------
# Deployment history files
# -------------------------------
HISTORY_DIR="../deploy_history"
mkdir -p "$HISTORY_DIR"

ACTIVE_FILE="$HISTORY_DIR/${SERVICE_NAME}_active_version"
HISTORY_FILE="$HISTORY_DIR/${SERVICE_NAME}_history"

touch "$ACTIVE_FILE"
touch "$HISTORY_FILE"

# -------------------------------
# Paths
# -------------------------------
NGINX_BASE_DIR="../nginx"
mkdir -p "${NGINX_BASE_DIR}/conf.d"
NGINX_CONF="${NGINX_BASE_DIR}/conf.d/${SERVICE_NAME}.conf"

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
# Build environment variable flags
# -------------------------------
ENV_FLAGS=()
ENV_FLAGS+=("-e" "PORT=$APP_PORT")   # Always pass PORT

for VAR in "${ENV_VARS[@]}"; do
  ENV_FLAGS+=("-e" "$VAR")
done

# -------------------------------
# Run new container (same network as nginx_proxy)
# -------------------------------
echo "🚀 Starting container $CONTAINER_NAME..."
nerdctl run -d \
  --name "$CONTAINER_NAME" \
  --network nginx_network \   # <-- IMPORTANT: same network as nginx
  "${ENV_FLAGS[@]}" \
  -p "$APP_PORT:$APP_PORT" \
  "$IMAGE_TAG"

# -------------------------------
# Health check
# -------------------------------
echo "⏳ Waiting for container to become healthy..."
success=false
for i in {1..10}; do
  if curl -s http://localhost:$APP_PORT/health | grep "ok" >/dev/null; then
    success=true
    echo "✅ Container is healthy!"
    break
  fi
  sleep 5
done

if [ "$success" != true ]; then
  echo "❌ Health check failed!"
  nerdctl stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  nerdctl rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# -------------------------------
# Update/create Nginx upstream for service
# -------------------------------
echo "🔀 Updating Nginx upstream block for $SERVICE_NAME..."



# If service config doesn't exist, create a minimal file with upstream
if [ ! -f "$NGINX_CONF" ]; then
  cat > "$NGINX_CONF" <<EOL
upstream ${SERVICE_NAME}_backend {
    server ${CONTAINER_NAME}:$APP_PORT;
}
EOL
else
  # Replace existing upstream block or insert one if missing
  if grep -q "upstream ${SERVICE_NAME}_backend" "$NGINX_CONF"; then
    # Cross-platform sed (macOS/Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "/upstream ${SERVICE_NAME}_backend {/,/}/c\\
upstream ${SERVICE_NAME}_backend {\\
    server ${CONTAINER_NAME}:$APP_PORT;\\
}" "$NGINX_CONF"
    else
      sed -i "/upstream ${SERVICE_NAME}_backend {/,/}/c upstream ${SERVICE_NAME}_backend {\n    server ${CONTAINER_NAME}:$APP_PORT;\n}" "$NGINX_CONF"
    fi
  else
    # Append upstream block if not found
    cat >> "$NGINX_CONF" <<EOL

upstream ${SERVICE_NAME}_backend {
    server ${CONTAINER_NAME}:$APP_PORT;
}
EOL
  fi
fi

# Reload nginx
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
