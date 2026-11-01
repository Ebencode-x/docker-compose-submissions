#!/usr/bin/env bash
# Verifies exercise 2.6: 2_03-10/docker-compose.yaml configures a Postgres
# database for the backend to save messages to. This is checked by actually
# pressing the "postgres" exercise button and driving the message form in
# the frontend with a real browser (Playwright), instead of hitting the
# backend API directly.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/2_03-10"
COMPOSE_FILE="$TARGET_DIR/docker-compose.yaml"
PLAYWRIGHT_DIR="$REPO_ROOT/tests/playwright"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

skip() {
  echo "SKIP: $1"
  exit 0
}

cleanup() {
  (cd "$TARGET_DIR" && docker compose down >/dev/null 2>&1)
}
trap cleanup EXIT

[ -f "$COMPOSE_FILE" ] || fail "2_03-10/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

# Once nginx is in place (exercise 2.9), the frontend/backend/redis/postgres
# wiring this test checks directly is superseded by the nginx and closed
# ports tests (2.9, 2.10), which exercise the whole stack through nginx.
grep -qi "nginx" "$COMPOSE_FILE" \
  && skip "docker-compose.yaml already includes nginx -- covered by the 2.9/2.10 tests instead"

grep -qi "postgres" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a postgres service"
pass "docker-compose.yaml defines a postgres service"

grep -q "POSTGRES_HOST" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not pass POSTGRES_HOST to the backend"
pass "docker-compose.yaml passes POSTGRES_HOST to the backend"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# Find whichever published host port actually serves the frontend, instead
# of assuming a fixed port -- this works the same whether the frontend is
# published directly (e.g. 5001) or sits behind something else (e.g. nginx
# on 8000).
container_ids=$(cd "$TARGET_DIR" && docker compose ps -q)
[ -n "$container_ids" ] || fail "docker compose did not start any containers"

APP_URL=""
for _ in $(seq 1 60); do
  for container_id in $container_ids; do
    for host_port in $(docker port "$container_id" 2>/dev/null | sed -E 's/.*:([0-9]+)$/\1/' | sort -u); do
      if curl -s --max-time 2 "http://localhost:$host_port" 2>/dev/null | grep -qi "html"; then
        APP_URL="http://localhost:$host_port"
        break 3
      fi
    done
  done
  sleep 2
done
[ -n "$APP_URL" ] || fail "could not find any published port serving the frontend"
pass "frontend is reachable at $APP_URL"

command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

# Press the "postgres" exercise button in the actual UI and check that it
# reports success, instead of calling /api/ping?postgres=true directly.
node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" postgres \
  || fail "pressing the \"postgres\" button in the frontend did not report success"
pass "pressing the \"postgres\" button in the frontend reported success"

# The message form in the frontend relies on POST/GET /api/messages actually
# persisting to the database -- drive that form instead of calling the API.
unique_body="test-message-$$-$RANDOM"
node "$PLAYWRIGHT_DIR/check-message.mjs" "$APP_URL" send "$unique_body" \
  || fail "sending a message through the frontend did not make it appear in the message list"
pass "a message sent through the frontend is saved and listed"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
