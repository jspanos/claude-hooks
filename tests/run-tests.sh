#!/usr/bin/env bash
# =============================================================================
# run-tests.sh — Run all hook rule tests
# =============================================================================
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Claude Hooks — Test Suite"
echo "========================================="

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

run_test_file() {
  local file="$1"
  local name
  name="$(basename "$file" .test.sh)"

  # Run in subprocess to isolate state
  local output exit_code
  output="$(bash "$file" 2>&1)"
  exit_code=$?

  echo "$output"

  # Extract counts from output (last lines of summary)
  if [[ $exit_code -eq 0 ]]; then
    local pass_count
    pass_count="$(echo "$output" | grep -oE 'All [0-9]+ tests passed' | grep -oE '[0-9]+' || echo 0)"
    TOTAL_PASS=$((TOTAL_PASS + pass_count))
  else
    local fail_count
    fail_count="$(echo "$output" | grep -oE '[0-9]+/[0-9]+ tests failed' | head -1 | cut -d/ -f1 || echo 1)"
    TOTAL_FAIL=$((TOTAL_FAIL + fail_count))
    FAILED_SUITES+=("$name")
  fi
}

for test_file in "$TESTS_DIR"/rules/*.test.sh; do
  [[ -f "$test_file" ]] || continue
  echo ""
  echo "-- $(basename "$test_file") ------------------"
  run_test_file "$test_file"
done

echo ""
echo "========================================="
if [[ $TOTAL_FAIL -eq 0 ]]; then
  printf "\033[32m  ALL TESTS PASSED (%d total)\033[0m\n" "$TOTAL_PASS"
  exit 0
else
  printf "\033[31m  FAILED: %d test(s) across: %s\033[0m\n" "$TOTAL_FAIL" "${FAILED_SUITES[*]}"
  exit 1
fi
