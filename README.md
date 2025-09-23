# CONTAINER INFRA

This is a framework for running containerized workloads with zero downtime using containerd and nerdctl.

## Steps

### Setup Nginx Server

1. cd container-infra
2. sudo ./nginx/run-proxy.sh

### Deploy Yor Workload

1. cd container-infra
2. touch /path/to/.<your_service>.env
3. nano /path/to/.<your_service>.env [paste your environment variables and save and exit]
4. sudo ./service/deploy.sh <your_service> <imaage_name> <version_name> <path_to_env> [health_check_path]
5. sudo ./nginx/config-service-http.sh <your_service> <your_service_port> <container_name> [your_service_domain]
6. sudo ./nginx/config-service-https.sh <your_service> <your_service_port> <container_name> [your_service_domain]

## Example

### Initiate Nginx Server

1. cd container-infra
2. sudo ./nginx/run-proxy.sh

### Deploy Backend Workload

1. cd container-infra
2. touch /home/energymixtech/.backend.env
3. nano /home/energymixtech/.backend.env [paste your environment variables and save and exit]
4. sudo ./service/deploy.sh backend ghcr.io/kingsley31/meter-bill-api 2025.09.12.011309 /home/energymixtech/.backend.env /health
5. sudo ./digital-ocean/set-dns-a-record.sh api.energymixtech.com 188.166.46.167
6. sudo ./nginx/config-service-http.sh backend 3000 backend_2025.09.12.011309 api.energymixtech.com [Note: This is optional]
7. sudo ./nginx/config-service-https.sh backend 3000 backend_2025.09.12.011309 api.energymixtech.com

### Deploy Fronted Workload

1. cd container-infra
2. touch /home/energymixtech/.frontend.env
3. nano /home/energymixtech/.frontend.env [paste your environment variables and save and exit]
4. sudo ./service/deploy.sh frontend ghcr.io/kingsley31/meter-bill-frontend 2025.09.10.132430 /home/energymixtech/.frontend.env /api/health
5. sudo ./digital-ocean/set-dns-a-record.sh energymixtech.com 188.166.46.167
6. sudo ./nginx/config-service-http.sh frontend 3001 frontend_2025.09.10.132430 / [Note: This is optional]
7. sudo ./nginx/config-service-https.sh frontend 3001 frontend_2025.09.10.132430 /

## Setup Mail Server

1. cd container-infra

2. export DO_API_TOKEN=your_digitalocean_api_token_here

3. sudo DO_API_TOKEN="$DO_API_TOKEN" ./digital-ocean/configure-droplet-ptr.sh 517606015 mail.energymixtech.com

4. sudo DO_API_TOKEN="$DO_API_TOKEN" ./digital-ocean/create_mail_dns.sh energymixtech.com 188.166.46.167

5. sudo DO_API_TOKEN="$DO_API_TOKEN" ./mail-server-scripts/dkim-rspamd-config.sh energymixtech.com 188.166.46.167 /home/energymixtech/container-infra/digital-ocean/create_dkim_record.sh

-------------------------------------------------------------------------------

1. touch /home/energymixtech/.maildb.env

2. sudo nano /home/energymixtech/.maildb.env [paste your environment variables(see ./mail-server-scripts/.example.maildb.env) and save and exit]

3. sudo ./mail-server-scripts/setup_postfix_schema.sh /home/energymixtech/.maildb.env
4. sudo ./mail-server-scripts/setup_postfix.sh energymixtech.com /home/energymixtech/.maildb.env
5. sudo ./mail-server-scripts/setup_dovecot.sh energymixtech.com /home/energymixtech/.maildb.env
6. sudo ./mail-server-scripts/add_mail_user.sh <admin@energymixtech.com> somepassword /home/energymixtech/.maildb.env
7. sudo ./mail-server-scripts/setup_ufw.sh

## Setup SMTP Relay for postfix If your provider blocked port 25

1. sudo nano /home/energymixtech/.smtprelay.env [paste your environment variables(see ./mail-server-scripts/.example.smtprelay.env) and save and exit]
2. sudo ./mail-server-scripts/configure_postfix_relay.sh /home/energymixtech/.smtprelay.env

## Setup RainLoop For Webmail

1. sudo ./mail-server-scripts/deploy_rainloop.sh
2. sudo ./nginx/config-service-https.sh roundcube 8888 roundcube webmail.energymixtech.com
3. sudo ./mail-server-scripts/deploy_rainloop.sh

## Login To Rainloop Admin Cpanel And Your Domain

Access RainLoop's admin panel (usually https://webmail.energymixtech.com/?admin) and configure the SSL settings:

Admin Login:
Username: admin
Password: 12345 (default) Note: change this to a strong password
