#!/bin/bash

# Configuration
DB_NAME=$1
DB_USER=$2
DB_PWD=$3
PORT=$4
DOMAIN_NAME=$5
IMAGE_NAME=$6
DOCKER_HUB_USERNAME=$7
DOCKER_CONTAINER_NAME=$8
APP_COMPOSE="/home/$IMAGE_NAME/docker-compose-${IMAGE_NAME}.yml"
NGINX_CONF="${IMAGE_NAME}-nginx.conf"

echo "$1, $2, $3, $4, $5, $6, $7, $8"

echo "Creating ${APP_COMPOSE} file..."
cat << EOF > $APP_COMPOSE
services:
  web:
    image: ${DOCKER_HUB_USERNAME}/${IMAGE_NAME}
    container_name: ${DOCKER_CONTAINER_NAME}
    environment:
      - DATABASE_URL=postgres://${DB_USER}:${DB_PWD}@localhost:5432/${DB_NAME}
      - DATABASE_QUERY_URL=postgres://${DB_USER}_query:${DB_PWD}@localhost:5432/${DB_NAME}
      - SECRET_KEY_BASE=6jObIP3Cd47fkXDM3TF8nWDPL27ZhfvCVW4MZEK766Uxz8YRTI3JlRShjHcNzZoH
      - PHX_HOST=${DOMAIN_NAME}
      - MIX_ENV=prod
      - PORT=$PORT
      - MAILJET_API_KEY=135721f0f369c66a2a181e096cd61505
      - MAILJET_SECRET=dd53cb5862212dcbe5610bc8aee8371f
    network_mode: host
EOF

echo "Creating Nginx conf file for ${DOMAIN_NAME}..."
cat << EOF > /etc/nginx/sites-available/${NGINX_CONF}
# /etc/nginx/sites-available/${NGINX_CONF}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; # Managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # Managed by Certbot

    location / {
        proxy_pass http://localhost:$PORT; # IMAGE_NAME container uses host network
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/${NGINX_CONF} /etc/nginx/sites-enabled/