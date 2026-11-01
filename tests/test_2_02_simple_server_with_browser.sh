#!/usr/bin/env bash
# Verifies that 2_02/docker-compose.yaml starts
# devopsdockeruh/simple-web-service and exposes it on the host so it can be
# reached with a browser.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/2_02"
COMPOSE_FILE="$TARGET_DIR/docker-compose.yaml"

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

[ -f "$COMPOSE_FILE" ] || fail "2_02/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

grep -q "devopsdockeruh/simple-web-service" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not reference the devopsdockeruh/simple-web-service image"
pass "docker-compose.yaml references devopsdockeruh/simple-web-service"

(cd "$TARGET_DIR" && docker compose up -d) || fail "docker compose up failed"
pass "docker compose up succeeded"

container_id=$(cd "$TARGET_DIR" && docker compose ps -q | head -n1)
[ -n "$container_id" ] || fail "docker compose did not start any container"

# Find the host port Docker published for the service, so the test does not
# depend on a specific port number being chosen in docker-compose.yaml.
host_port=$(docker port "$container_id" | head -n1 | sed -E 's/.*:([0-9]+)$/\1/')
[ -n "$host_port" ] \
  || fail "docker-compose.yaml does not publish any port to the host -- the service can't be reached from a browser"
pass "docker-compose.yaml publishes port $host_port to the host"

# Give the service a moment to start serving requests.
response=""
for _ in $(seq 1 15); do
  response=$(curl -s --max-time 2 "http://localhost:$host_port/" 2>/dev/null) && [ -n "$response" ] && break
  sleep 1
done

[ -n "$response" ] || fail "could not reach the web service at http://localhost:$host_port/"
pass "web service responded at http://localhost:$host_port/"

echo "$response" | grep -qi "path" \
  || fail "unexpected response from the web service: $response"
pass "web service returned the expected response body"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
