#!/usr/bin/env bash
# Verifies exercise 2.10: with the reverse proxy in place, nothing but
# Nginx is directly reachable from the host. frontend, backend, redis and
# db must not publish ports to the host. Readiness is checked by actually
# pressing the "backend" exercise button in the frontend with a real
# browser (Playwright), instead of hitting the backend API directly.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/2_03-10"
COMPOSE_FILE="$TARGET_DIR/docker-compose.yaml"
PLAYWRIGHT_DIR="$REPO_ROOT/tests/playwright"
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

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# Wait for the app to be fully up before checking that only Nginx answers,
# by actually pressing the "backend" exercise button in the frontend.
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

command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" backend \
  || fail "pressing the \"backend\" button in the frontend did not report success through the proxy"
pass "pressing the \"backend\" button in the frontend reported success through the proxy -- app is ready"

for service in backend frontend redis db; do
  container_id=$(cd "$TARGET_DIR" && docker compose ps -q "$service")
  [ -n "$container_id" ] || fail "could not find a running container for service '$service'"

  published=$(docker port "$container_id" 2>/dev/null)
  [ -z "$published" ] \
    || fail "service '$service' publishes ports to the host, but exercise 2.10 requires it to be unreachable directly (published: $published)"
  pass "service '$service' does not publish any port to the host"
done

nginx_container_id=$(cd "$TARGET_DIR" && docker compose ps -q nginx)
[ -n "$nginx_container_id" ] || fail "could not find a running container for the nginx service"
nginx_published=$(docker port "$nginx_container_id" 2>/dev/null)
echo "$nginx_published" | grep -q "8000" \
  || fail "nginx does not publish host port 8000 (published: $nginx_published)"
pass "only nginx publishes a port to the host, on 8000"

echo "$nginx_published" | grep -qE '^80/tcp' \
  || fail "nginx's published port mapping does not look like it forwards container port 80 (published: $nginx_published)"
pass "nginx maps container port 80 to host port 8000"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
