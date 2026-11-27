#!/usr/bin/env bash
# Run on your Mac: build images locally, stream them to EC2, start the app there.
# Nothing is built on the EC2 instance, so 1 GB RAM / small disk is enough.
#
# Usage: ./ship.sh            (settings are read from ship.env)
set -euo pipefail
cd "$(dirname "$0")"

[[ -f ship.env ]] || { cat > ship.env <<'ENV'
# Settings for ./ship.sh
EC2_HOST=1.2.3.4                 # EC2 public IP or DNS
EC2_USER=ubuntu                  # ubuntu (Ubuntu) or ec2-user (Amazon Linux)
SSH_KEY=~/.ssh/my-key.pem        # your EC2 key pair file
REMOTE_DIR=student-register      # folder on EC2 (relative to home)
PLATFORM=linux/amd64             # t2/t3.micro = linux/amd64, t4g = linux/arm64
ENV
  echo "Created ship.env - fill in your EC2 details, then run ./ship.sh again."; exit 1; }

# shellcheck disable=SC1091
source ship.env
SSH_KEY="${SSH_KEY/#\~/$HOME}"
TARGET="$EC2_USER@$EC2_HOST"
SSH=(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$TARGET")

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }

info "Building images for $PLATFORM on this Mac..."
docker buildx build --platform "$PLATFORM" -t student-register-backend:latest  --load ./backend
docker buildx build --platform "$PLATFORM" -t student-register-frontend:latest --load ./frontend

info "Copying config files to $TARGET:$REMOTE_DIR ..."
"${SSH[@]}" "mkdir -p $REMOTE_DIR/mysql"
scp -i "$SSH_KEY" docker-compose.prod.yml deploy.sh "$TARGET:$REMOTE_DIR/"
scp -i "$SSH_KEY" mysql/low-memory.cnf "$TARGET:$REMOTE_DIR/mysql/"

info "Removing old images on EC2 to free disk..."
"${SSH[@]}" "sudo docker image prune -af >/dev/null; df -h / | tail -1"

info "Streaming images to EC2 (no temp file on the server)..."
docker save student-register-backend:latest student-register-frontend:latest \
  | gzip | "${SSH[@]}" "gunzip | sudo docker load"

info "Starting the app on EC2..."
"${SSH[@]}" "cd $REMOTE_DIR && chmod +x deploy.sh && sudo ./deploy.sh start"
ok "Done. Open http://$EC2_HOST"
