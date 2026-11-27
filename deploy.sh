#!/usr/bin/env bash
# Production deploy helper for Student Register
# Usage: ./deploy.sh [up|down|restart|logs|status|backup|clean]   (default: up)
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env.prod"
COMPOSE=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

require_docker() {
  command -v docker >/dev/null 2>&1 || fail "Docker is not installed."
  docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required (docker compose)."
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
  fi
}

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    info "Creating $ENV_FILE with random database passwords..."
    cat > "$ENV_FILE" <<ENV
# Production settings - keep this file private, do not commit it
APP_PORT=80
MYSQL_DATABASE=student_register
MYSQL_USER=student
MYSQL_PASSWORD=$(random_secret)
MYSQL_ROOT_PASSWORD=$(random_secret)
ENV
    chmod 600 "$ENV_FILE"
    ok "$ENV_FILE created (back it up - the DB passwords live here)."
  fi
}

wait_healthy() {
  info "Waiting for backend to become healthy..."
  for _ in $(seq 1 60); do
    id=$("${COMPOSE[@]}" ps -q backend)
    status=$(docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null || echo starting)
    [[ "$status" == "healthy" ]] && { ok "Backend is healthy."; return 0; }
    sleep 3
  done
  "${COMPOSE[@]}" logs --tail=50 backend
  fail "Backend did not become healthy in time."
}

ensure_swap() {
  # Small EC2 instances (t2/t3.micro, 1 GB RAM) can run out of memory while building.
  [[ "$(uname -s)" == "Linux" ]] || return 0
  local mem_mb swap_mb
  mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
  if (( mem_mb < 2048 && swap_mb < 1024 )); then
    info "Low memory (${mem_mb} MB RAM, ${swap_mb} MB swap) - adding a 2 GB swap file..."
    if [[ ! -f /swapfile ]]; then
      sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile >/dev/null
    fi
    sudo swapon /swapfile 2>/dev/null || true
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
    ok "Swap enabled."
  fi
}

cmd_up() {
  ensure_env
  ensure_swap
  # Build one image at a time to keep peak memory low
  for svc in backend frontend; do
    info "Building $svc..."
    "${COMPOSE[@]}" build --pull "$svc"
  done
  info "Starting containers..."
  "${COMPOSE[@]}" up -d --remove-orphans
  wait_healthy
  "${COMPOSE[@]}" ps
  port=$(grep -E '^APP_PORT=' "$ENV_FILE" | cut -d= -f2)
  ok "Student Register is running on http://localhost:${port:-80}"
  info "Cleaning up old images and build cache..."
  docker image prune -f >/dev/null
  docker builder prune -f >/dev/null
  docker images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' | grep student-register || true
}

cmd_backup() {
  ensure_env
  mkdir -p backups
  file="backups/student_register_$(date +%Y%m%d_%H%M%S).sql"
  info "Dumping database to $file ..."
  "${COMPOSE[@]}" exec -T mysql sh -c \
    'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction "$MYSQL_DATABASE"' > "$file"
  ok "Backup saved: $file"
}

require_docker

case "${1:-up}" in
  up)       cmd_up ;;
  down)     ensure_env; "${COMPOSE[@]}" down ;;
  restart)  ensure_env; "${COMPOSE[@]}" restart; wait_healthy ;;
  logs)     ensure_env; "${COMPOSE[@]}" logs -f --tail=100 "${@:2}" ;;
  status)   ensure_env; "${COMPOSE[@]}" ps ;;
  backup)   cmd_backup ;;
  clean)    docker system prune -af && docker builder prune -af ;;   # free disk (keeps volumes/DB data)
  *)        echo "Usage: $0 [up|down|restart|logs|status|backup|clean]"; exit 1 ;;
esac
