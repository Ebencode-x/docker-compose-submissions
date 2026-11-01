#!/usr/bin/env bash
# Verifies exercise 2.8: a simplified, first pass at putting Nginx in front
# of the project, before exercise 2.9 fixes up every button to work behind
# it. This only checks:
#   - the frontend is reachable simply by going to http://localhost:8000
#   - a direct request to the backend at http://localhost:8000/api/ping
#     works
# The exercise buttons (redis, postgres, messages) may or may not work yet
# behind the proxy at this stage -- that's exercise 2.9's job, checked by
# tests/test_2_09_project_nginx.sh instead.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/2_03-10"
COMPOSE_FILE="$TARGET_DIR/docker-compose.yaml"
APP_URL="http://localhost:8000"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

cleanup() {
  (cd "$TARGET_DIR" && docker compose down >/dev/null 2>&1)
}
trap cleanup EXIT

[ -f "$COMPOSE_FILE" ] || fail "2_03-10/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

grep -qi "nginx" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define an nginx service"
pass "docker-compose.yaml defines an nginx service"

grep -qE '8000:80\b' "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not publish nginx's port 80 as host port 8000"
pass "docker-compose.yaml publishes nginx on host port 8000"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# The frontend must be reachable simply by going to http://localhost:8000.
frontend_ok=false
for _ in $(seq 1 60); do
  if curl -s --max-time 2 "$APP_URL" 2>/dev/null | grep -qi "html"; then
    frontend_ok=true
    break
  fi
  sleep 2
done
$frontend_ok || fail "frontend was not reachable at $APP_URL"
pass "frontend is reachable at $APP_URL"

# A direct request to the backend through the proxy must work. Buttons in
# the UI are not checked here -- they may still be broken at this stage.
ping_ok=false
for _ in $(seq 1 60); do
  response=$(curl -s --max-time 2 "$APP_URL/api/ping" 2>/dev/null)
  if [ "$response" = "pong" ]; then
    ping_ok=true
    break
  fi
  sleep 2
done
$ping_ok || fail "$APP_URL/api/ping did not return pong (got: '$response')"
pass "$APP_URL/api/ping returns pong through the Nginx proxy"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
