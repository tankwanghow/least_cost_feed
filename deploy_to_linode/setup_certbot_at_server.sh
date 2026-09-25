#!/bin/bash

# Domain name
DOMAIN=$1

# Check if the certificate exists
if [ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
    echo "Certificate for $DOMAIN already exists."
else
    echo "Certificate for $DOMAIN does not exist. Creating now..."
    # Install Certbot if not already installed
    if ! command -v certbot &> /dev/null
    then
        sudo apt-get update
        sudo apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Generate SSL certificate
    sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN
fi

# Renewal is handled by the certbot.timer systemd unit the apt package installs;
# no crontab entry is needed (check with: systemctl list-timers | grep certbot).
