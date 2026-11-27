#!/usr/bin/env bash
# Production deploy helper for Student Register
# Usage: ./deploy.sh [up|down|restart|logs|status|clean]   (default: up)
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

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<'ENV'
# Production settings - keep this file private, do not commit it
APP_PORT=80

# Your own MySQL. From inside the backend container:
#   - MySQL on this EC2 host (installed or `docker run -p 3306:3306`): use host.docker.internal
#   - Amazon RDS / another server: use its hostname
DATABASE_URL=mysql://student:CHANGE_ME@host.docker.internal:3306/student_register
ENV
    chmod 600 "$ENV_FILE"
    fail "Created $ENV_FILE - edit DATABASE_URL, then run ./deploy.sh again."
  fi
  grep -q 'CHANGE_ME' "$ENV_FILE" && fail "Set a real DATABASE_URL in $ENV_FILE first."
  return 0
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

require_docker

case "${1:-up}" in
  up)       cmd_up ;;
  down)     ensure_env; "${COMPOSE[@]}" down ;;
  restart)  ensure_env; "${COMPOSE[@]}" restart; wait_healthy ;;
  logs)     ensure_env; "${COMPOSE[@]}" logs -f --tail=100 "${@:2}" ;;
  status)   ensure_env; "${COMPOSE[@]}" ps ;;
  clean)    docker system prune -af && docker builder prune -af ;;   # free disk: unused images + build cache
  *)        echo "Usage: $0 [up|down|restart|logs|status|clean]"; exit 1 ;;
esac
