#!/usr/bin/env bash
# Verifies exercise 2.3: 2_03-10/docker-compose.yaml brings up the example
# frontend and backend together, and the frontend can reach the backend
# through it. This is checked by actually pressing the "backend" exercise
# button in the frontend with a real browser (Playwright) and waiting for
# it to report success, the same way a student would.
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

grep -q "backend" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a backend service"
pass "docker-compose.yaml defines a backend service"

grep -q "frontend" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a frontend service"
pass "docker-compose.yaml defines a frontend service"

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

# Press the "backend" exercise button in the actual UI and check that it
# reports success, instead of calling the backend API directly.
command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" backend \
  || fail "pressing the \"backend\" button in the frontend did not report success"
pass "pressing the \"backend\" button in the frontend reported success"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
