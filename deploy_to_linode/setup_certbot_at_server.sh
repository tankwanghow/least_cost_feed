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

# Check if cron job for renewal exists
CRON_JOB='0 */12 * * * root test -x /usr/bin/certbot -a \! -d /run/systemd/system && perl -e "sleep int(rand(3600))" && certbot -q renew'
if sudo crontab -l | grep -qF "$CRON_JOB"; then
    echo "The cron job for certificate renewal already exists."
else
    echo "Adding cron job for certificate renewal..."
    # Append the cron job to the system crontab
    (sudo crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo crontab -
    echo "Cron job added successfully."
fi