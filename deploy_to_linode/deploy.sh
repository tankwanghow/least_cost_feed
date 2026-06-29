#!/bin/bash
set -eo pipefail

SETUP_FILE=$1
script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
umbrella_root="$(cd "$script_path/../.." && pwd)"
if [ ! -f "$umbrella_root/shared_config/docker_deploy.sh" ]; then
  cat <<'EOF'
Error: global assets / monorepo layout not found.

This app must be deployed from inside the phoenix_app_umbrella monorepo, which
provides shared_config/ and .global_assets/. To set it up:

  1. Clone the umbrella (global assets) repo:
       git clone https://github.com/tankwanghow/phoenix_app_umbrella.git

  2. Clone this app inside it, beside shared_config/:
       cd phoenix_app_umbrella
       git clone https://github.com/tankwanghow/least_cost_feed.git least_cost_feed

  3. Download the global asset binaries:
       bash .global_assets/setup.sh

  4. Deploy from inside the app, e.g.:
       cd least_cost_feed && ./deploy_to_linode/deploy.sh deploy.conf

Expected layout:
  phoenix_app_umbrella/
  |- shared_config/
  |- .global_assets/
  \- least_cost_feed/    <- this repo
EOF
  exit 1
fi
# shellcheck source=../../shared_config/docker_deploy.sh
source "$umbrella_root/shared_config/docker_deploy.sh"
docker_deploy_init "$script_path"

if [ ! -f "$SETUP_FILE" ]; then
    echo "Error: Setup file $SETUP_FILE not found."
    exit 1
fi

while IFS='=' read -r key value
do
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ "$key" =~ ^[[:space:]]*$ ]] && continue
    key=$(echo $key | tr -d '[:space:]')
    value=$(echo $value | tr -d '[:space:]')
    declare "$key=$value"
done < "$SETUP_FILE"

stty -echo
echo -n "Please enter password of the server: "
read LINODE_PWD
stty echo
echo

ensure_global_assets
stage_dockerignore

IMAGE_TAG="latest"
FULL_IMAGE="$DOCKER_HUB_USERNAME/$IMAGE_NAME:$IMAGE_TAG"

echo "Building Docker image (monorepo context: $MONOREPO_ROOT)..."
docker build --builder default \
    -t $FULL_IMAGE \
    -f "$PROJECT_ROOT/Dockerfile" \
    "$MONOREPO_ROOT"

IMAGE_SIZE=$(docker image inspect $FULL_IMAGE --format='{{.Size}}')
echo "Transferring image to server (~$(( IMAGE_SIZE / 1024 / 1024 )) MB uncompressed)..."
docker save $FULL_IMAGE | gzip | pv | sshpass -p $LINODE_PWD ssh -o StrictHostKeyChecking=no root@$LINODE_IP "gunzip | docker load"

sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/$IMAGE_NAME/deploy_at_server.sh $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME"