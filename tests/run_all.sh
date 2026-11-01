#!/usr/bin/env bash
# Runs every tests/test_2_NN_*.sh script in order from 2_01 to 2_10.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0

for n in $(seq -w 1 10); do
  for test_file in "$SCRIPT_DIR"/test_2_"$n"_*.sh; do
    [ -e "$test_file" ] || continue
    echo "=== Running $(basename "$test_file") ==="
    if bash "$test_file"; then
      echo "=== PASS: $(basename "$test_file") ==="
    else
      echo "=== FAIL: $(basename "$test_file") ==="
      failures=$((failures + 1))
    fi
    echo
  done
done

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi

echo "All tests passed"
