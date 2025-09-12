# Deploy Script Documentation

## Overview

This script automates deployment of a containerized service and configures Nginx for load balancing. It ensures the service is healthy and reachable on the network before updating Nginx.

---

## Script Usage

```bash
./deploy-service.sh <nginx_base_dir> <service_name> <image_name> <version> [ENV_VARS...]
```

### Arguments

1. **nginx_base_dir**: Base directory where Nginx configuration and volumes are located.
2. **service_name**: The name of the service being deployed.
3. **image_name**: Docker image name.
4. **version**: Service version tag.
5. **ENV_VARS**: Optional environment variables (e.g., `DB_HOST=localhost DB_PASS=secret`).

### Examples

- Deploy default version:

```bash
./deploy-service.sh /home/username/nginx myapp myapp v1.2.3
```

- Deploy with environment variables:

```bash
./deploy-service.sh /home/username/nginx myapp myapp v1.2.3 DB_HOST=localhost DB_PASS=secret
```

---

## Features

1. **Automatic port assignment**: Finds a free port between 3000 and 5100 for the service.
2. **Zero-downtime updates**: Stops the previous version only after the new container is healthy.
3. **Network readiness check**: Ensures the container is reachable from the `nginx_proxy` container before updating Nginx.
4. **Health check**: Validates the `/health` endpoint of the service.
5. **Nginx upstream update**: Updates or creates the upstream block for the deployed service.
6. **Deployment history**: Tracks the current active version and historical deployments in `deploy_history` under `NGINX_BASE_DIR`.

---

## Deployment Steps

1. Script finds an available port for the service.
2. Stops and records the current active container if any.
3. Runs the new container with environment variables and assigned port.
4. Checks network reachability from `nginx_proxy`.
5. Performs host-level health check.
6. Updates or creates Nginx upstream configuration.
7. Reloads Nginx configuration.
8. Stops old container after the new one is healthy.
9. Records deployment version and port in history files.

---

## Notes

- Ensure `nginx_proxy` container is running on the `nginx_network` before running this script.
- `/health` endpoint must return a string containing "ok" to pass the health check.
- The script requires `nerdctl` installed and configured.
- Environment variables passed to the script are forwarded to the container.

---

## Troubleshooting

- **Container not reachable from nginx_proxy**:
  - Verify the container is attached to `nginx_network`.

- **Health check fails**:
  - Ensure the service exposes `/health` and returns "ok".

- **Nginx upstream errors**:
  - Make sure `nginx_proxy` is running and can resolve container names.
  - Check the upstream block in `$NGINX_BASE_DIR/conf.d`.

---

## Deployment History Files

- `deploy_history/<service_name>_active_version`: Stores the currently active version and port.
- `deploy_history/<service_name>_history`: Logs all deployment timestamps, versions, and ports.
