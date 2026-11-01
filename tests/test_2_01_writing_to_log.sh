#!/usr/bin/env bash
# Verifies that 2_01/docker-compose.yaml starts
# devopsdockeruh/simple-web-service and that the container's logs end up
# in 2_01/log.txt on the host filesystem.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/2_01"
COMPOSE_FILE="$TARGET_DIR/docker-compose.yaml"
LOG_FILE="$TARGET_DIR/log.txt"

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

[ -f "$COMPOSE_FILE" ] || fail "2_01/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

grep -q "devopsdockeruh/simple-web-service" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not reference the devopsdockeruh/simple-web-service image"
pass "docker-compose.yaml references devopsdockeruh/simple-web-service"

# Start from a clean, empty file. If log.txt doesn't exist yet Docker will
# bind-mount a directory instead of a file, so make sure it is present.
rm -rf "$LOG_FILE"
touch "$LOG_FILE"

(cd "$TARGET_DIR" && docker compose up -d) || fail "docker compose up failed"
pass "docker compose up succeeded"

[ -f "$LOG_FILE" ] || fail "log.txt was not created next to docker-compose.yaml"
pass "log.txt exists next to docker-compose.yaml"

# Give the service a few seconds to write its first log lines.
content_appeared=false
for _ in $(seq 1 15); do
  if [ -s "$LOG_FILE" ]; then
    content_appeared=true
    break
  fi
  sleep 1
done

$content_appeared || fail "log.txt stayed empty -- container logs are not reaching the filesystem"
pass "log.txt received content from the container"

lines_first=$(wc -l < "$LOG_FILE")
sleep 4
lines_second=$(wc -l < "$LOG_FILE")

[ "$lines_second" -gt "$lines_first" ] \
  || fail "log.txt did not grow over time -- logs are not being continuously written to the filesystem"
pass "log.txt keeps growing, confirming continuous logging to the filesystem"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
