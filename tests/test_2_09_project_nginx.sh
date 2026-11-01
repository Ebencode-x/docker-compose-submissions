#!/usr/bin/env bash
# Verifies exercises 2.7 (reverse proxy) and 2.9 (fixup): Nginx sits in
# front of both the frontend and the backend, listening on host port 8000,
# and every button/request in the app works when routed through it. This is
# checked by actually pressing the exercise buttons and driving the message
# form in the frontend with a real browser (Playwright), instead of hitting
# the backend API directly.
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

grep -qi "nginx" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define an nginx service"
pass "docker-compose.yaml defines an nginx service"

grep -qE '8000:80\b' "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not publish nginx's port 80 as host port 8000"
pass "docker-compose.yaml publishes nginx on host port 8000"

grep -q "/etc/nginx/nginx.conf" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not bind mount a config file to /etc/nginx/nginx.conf"
pass "docker-compose.yaml bind mounts a config file to /etc/nginx/nginx.conf"

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

command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

# Every exercise button in the app must work once all requests are routed
# through Nginx: backend (1.14), redis (2.4) and postgres (2.6).
node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" backend \
  || fail "pressing the \"backend\" button in the frontend did not report success through the proxy"
pass "pressing the \"backend\" button in the frontend reported success through the proxy"

node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" redis \
  || fail "pressing the \"redis\" button in the frontend did not report success through the proxy"
pass "pressing the \"redis\" button in the frontend reported success through the proxy"

node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" postgres \
  || fail "pressing the \"postgres\" button in the frontend did not report success through the proxy"
pass "pressing the \"postgres\" button in the frontend reported success through the proxy"

unique_body="nginx-test-$$-$RANDOM"
node "$PLAYWRIGHT_DIR/check-message.mjs" "$APP_URL" send "$unique_body" \
  || fail "sending a message through the frontend did not make it appear in the message list through the proxy"
pass "'Get all messages'/'Send message' work through the proxy"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
