#!/usr/bin/env bash
# Verifies exercise 2.7: the Postgres database is backed by a manually
# configured bind mount (e.g. ./database) instead of the image's default
# anonymous volume, and that data actually persists there across restarts.
# The persistence check drives the message form in the frontend with a real
# browser (Playwright) instead of hitting the backend API directly.
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

# Postgres initializes its data directory as its own container user
# (uid 70, mode 0700), so on native Linux (unlike Docker Desktop's mac
# volume translation) the host user running this script has no permission
# to read or remove it directly. Route those operations through a
# throwaway root container instead.
clean_host_dir() {
  docker run --rm -v "$TARGET_DIR:/target" alpine rm -rf "/target/${host_dir#./}" >/dev/null 2>&1
}

# Ensure the bind mount's host directory exists and is empty before the run
# starts: create it if it's missing, or wipe it if it's already there (e.g.
# leftover from a crashed previous run).
reset_host_dir() {
  docker run --rm -v "$TARGET_DIR:/target" alpine \
    sh -c "rm -rf \"/target/${host_dir#./}\" && mkdir -p \"/target/${host_dir#./}\""
}

host_dir_has_file() {
  # Search a few levels deep: postgres pre-18 puts PG_VERSION directly under
  # the mounted dir (.../data/PG_VERSION), postgres 18+ nests it further
  # under a major-version directory (.../18/docker/PG_VERSION).
  docker run --rm -v "$TARGET_DIR:/target" alpine \
    sh -c "find \"/target/${host_dir#./}\" -maxdepth 3 -name '$1' 2>/dev/null | grep -q ."
}

cleanup() {
  (cd "$TARGET_DIR" && docker compose down >/dev/null 2>&1)
  [ -n "${host_dir:-}" ] && clean_host_dir
}
trap cleanup EXIT

[ -f "$COMPOSE_FILE" ] || fail "2_03-10/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

# Once nginx is in place (exercise 2.9), the frontend/backend/redis/postgres
# wiring this test checks directly is superseded by the nginx and closed
# ports tests (2.9, 2.10), which exercise the whole stack through nginx.
grep -qi "nginx" "$COMPOSE_FILE" \
  && skip "docker-compose.yaml already includes nginx -- covered by the 2.9/2.10 tests instead"

# A bind mount for postgres data maps a host path (./database or similar)
# to /var/lib/postgresql, as opposed to a named/anonymous volume. Accept
# either .../postgresql/data (the classic target, still correct for
# postgres <18) or .../postgresql itself (required for postgres 18+, which
# stores data in a major-version-specific subdirectory of that parent --
# see https://github.com/docker-library/postgres/pull/1259).
grep -q "/var/lib/postgresql" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not mount anything to /var/lib/postgresql"
pass "docker-compose.yaml mounts something to /var/lib/postgresql"

grep -E "^\s*-\s*\./[A-Za-z0-9_.-]*:/var/lib/postgresql(/data)?\s*\$" "$COMPOSE_FILE" >/dev/null \
  || fail "the mount for /var/lib/postgresql does not look like a bind mount to a relative host path (./...)"
pass "the mount for /var/lib/postgresql is a bind mount to a relative host path"

host_dir=$(grep -oE "\./[A-Za-z0-9_.-]*:/var/lib/postgresql(/data)?" "$COMPOSE_FILE" | head -n1 | cut -d: -f1)
[ -n "$host_dir" ] || fail "could not determine the bind mount's host directory from docker-compose.yaml"
pass "bind mount host directory is $host_dir"

# There should be no top-level named volume declared for this data, since
# the exercise explicitly asks for a bind mount instead.
if grep -qE "^volumes:" "$COMPOSE_FILE"; then
  fail "docker-compose.yaml declares a top-level 'volumes:' section -- exercise 2.7 asks for a bind mount, not a named volume"
fi
pass "docker-compose.yaml does not declare a named volume for the database"

# Start from a clean slate: don't assume anything about whether the bind
# mount directory already exists on the host, or what's in it left over
# from a previous run -- otherwise a stale PG_VERSION file could make the
# persistence check below pass without the mount actually working.
reset_host_dir
pass "bind mount host directory $host_dir is created and empty"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# Find whichever published host port actually serves the frontend, instead
# of assuming a fixed port -- this works the same whether the frontend is
# published directly (e.g. 5001) or sits behind something else (e.g. nginx
# on 8000).
find_app_url() {
  local container_ids container_id host_port
  container_ids=$(cd "$TARGET_DIR" && docker compose ps -q)
  [ -n "$container_ids" ] || return 1

  for _ in $(seq 1 60); do
    for container_id in $container_ids; do
      for host_port in $(docker port "$container_id" 2>/dev/null | sed -E 's/.*:([0-9]+)$/\1/' | sort -u); do
        if curl -s --max-time 2 "http://localhost:$host_port" 2>/dev/null | grep -qi "html"; then
          echo "http://localhost:$host_port"
          return 0
        fi
      done
    done
    sleep 2
  done
  return 1
}

APP_URL=$(find_app_url) || fail "could not find any published port serving the frontend"
pass "frontend is reachable at $APP_URL"

command -v node >/dev/null 2>&1 || fail "node is required to run the browser check in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npm install --no-audit --no-fund >/dev/null 2>&1) \
  || fail "npm install failed in tests/playwright"
(cd "$PLAYWRIGHT_DIR" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1) \
  || fail "playwright chromium install failed"

node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" postgres \
  || fail "pressing the \"postgres\" button in the frontend did not report success"
pass "pressing the \"postgres\" button in the frontend reported success"

data_appeared=false
for _ in $(seq 1 15); do
  if host_dir_has_file PG_VERSION; then
    data_appeared=true
    break
  fi
  sleep 1
done
$data_appeared || fail "no Postgres data files appeared on the host at $TARGET_DIR/${host_dir#./} -- is the bind mount actually working?"
pass "Postgres data files are visible on the host filesystem at $TARGET_DIR/${host_dir#./}"

unique_body="bind-mount-test-$$-$RANDOM"
node "$PLAYWRIGHT_DIR/check-message.mjs" "$APP_URL" send "$unique_body" \
  || fail "sending a message through the frontend did not make it appear in the message list"
pass "saved a message before restarting the stack"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

(cd "$TARGET_DIR" && docker compose up -d) || fail "docker compose up (restart) failed"
pass "docker compose up (restart) succeeded"

APP_URL=$(find_app_url) || fail "could not find any published port serving the frontend after restart"
pass "frontend is reachable at $APP_URL after restart"

node "$PLAYWRIGHT_DIR/check-message.mjs" "$APP_URL" check "$unique_body" \
  || fail "the message saved before the restart is gone -- data is not persisted on the bind mount"
pass "the message saved before the restart is still there -- data persists on the bind mount"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

# Now prove the reverse: this is only a real bind mount (and not, say, an
# extra volume the image created on the side) if wiping the host directory
# and starting fresh actually loses the data.
clean_host_dir
pass "manually deleted the bind mount host directory $host_dir"

(cd "$TARGET_DIR" && docker compose up -d) || fail "docker compose up (after deleting the volume) failed"
pass "docker compose up (after deleting the volume) succeeded"

APP_URL=$(find_app_url) || fail "could not find any published port serving the frontend after recreating the volume"
pass "frontend is reachable at $APP_URL after recreating the volume"

# Confirm the backend is actually connected to the (now empty) database
# before checking that the message is gone -- otherwise an empty result
# could just mean the backend hasn't finished reconnecting yet.
node "$PLAYWRIGHT_DIR/check-exercise-button.mjs" "$APP_URL" postgres \
  || fail "pressing the \"postgres\" button in the frontend did not report success after recreating the volume"
pass "pressing the \"postgres\" button in the frontend reported success after recreating the volume"

node "$PLAYWRIGHT_DIR/check-message.mjs" "$APP_URL" absent "$unique_body" \
  || fail "the message is still there after deleting the bind mount host directory -- data isn't actually tied to $host_dir"
pass "the message is gone after deleting the bind mount host directory -- data is genuinely tied to $host_dir"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
