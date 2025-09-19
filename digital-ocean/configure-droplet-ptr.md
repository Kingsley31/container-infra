# Configure Droplet PTR

This is script is used to setup reverve dns for a digital ocean droplet.

## Set PTR record

sudo ./configure-droplet-ptr.sh 517606015 mail.energymixtech.com

## Cleanup PTR record  

sudo ./configure-droplet-ptr.sh 517606015 ubuntu-s-1vcpu-2gb-ams3-01-Energymix1 --cleanup

## Detect settings

sudo ./detect-droplet-settings.sh
