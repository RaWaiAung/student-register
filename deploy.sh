#!/usr/bin/env bash
# Production deploy helper for Student Register
# Usage: ./deploy.sh [up|down|restart|logs|status|backup]   (default: up)
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

cmd_up() {
  ensure_env
  info "Building images..."
  "${COMPOSE[@]}" build --pull
  info "Starting containers..."
  "${COMPOSE[@]}" up -d --remove-orphans
  wait_healthy
  "${COMPOSE[@]}" ps
  port=$(grep -E '^APP_PORT=' "$ENV_FILE" | cut -d= -f2)
  ok "Student Register is running on http://localhost:${port:-80}"
  docker image prune -f >/dev/null
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
  *)        echo "Usage: $0 [up|down|restart|logs|status|backup]"; exit 1 ;;
esac
