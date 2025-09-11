# run-nginx-proxy.sh

This script runs an Nginx reverse proxy inside a container using `nerdctl`.  
It accepts a single argument: the base path where your Nginx configuration, certificates, and HTML files are stored.  

---

## Features

- Maps Nginx config, conf.d, SSL certificates, and HTML content from your local directory to the container.
- Exposes ports `80` (HTTP) and `443` (HTTPS).
- Runs in detached mode.
- Automatically restarts on failure.

---

## Usage

```bash
chmod +x run-nginx-proxy.sh

./run-nginx-proxy.sh /home/username/nginx
```
