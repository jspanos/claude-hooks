#!/usr/bin/env bash
# =============================================================================
# bash-9.test.sh — Tests for bash_check_blocking_waits / bash_suggest_timeout
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

# Source assert harness FIRST (installs mocks before rule is loaded)
source "$TESTS_DIR/lib/assert.sh"

PROJECT_DIR="/home/testuser/myproject"
CWD="/home/testuser/myproject"
HOME="/home/testuser"

source "$RULES_DIR/bash-9-blocking-waits.sh"

# ── Local assertion for the timeout advisor ─────────────────────────────────
assert_timeout() {
  local desc="$1" expected="$2" got="$3"
  if [[ "$got" == "$expected" ]]; then
    printf "    \033[32m✓\033[0m %s\n" "$desc"
    PASS=$((PASS+1))
  else
    printf "    \033[31m✗\033[0m %s\n" "$desc"
    printf "      expected: '%s'\n" "$expected"
    printf "      got:      '%s'\n" "$got"
    FAIL=$((FAIL+1))
  fi
}

# =============================================================================

echo "bash-9: Blocking Waits & Timeouts"

suite "Foreground blocking waits — blocked"

bash_check_blocking_waits "gh run watch 31690698511 --interval 30 --exit-status" "false"
assert_blocked "gh run watch" "bash-9"

bash_check_blocking_waits "gh pr checks 80 --watch --interval 15 2>&1 | tail -15" "false"
assert_blocked "gh pr checks --watch" "bash-9"

bash_check_blocking_waits 'until ! gh pr checks 351 2>&1 | grep -q pending; do sleep 20; done; echo done' "false"
assert_blocked "until + sleep poll loop" "bash-9"

bash_check_blocking_waits 'while [ "$(gh run view 1 --json status -q .status)" != "completed" ]; do sleep 30; done' "false"
assert_blocked "while + sleep poll loop" "bash-9"

bash_check_blocking_waits 'for i in $(seq 1 20); do curl -s localhost:8080 && break; sleep 5; done' "false"
assert_blocked "for + sleep poll loop" "bash-9"

bash_check_blocking_waits "sleep 30" "false"
assert_blocked "bare long sleep" "bash-9"

bash_check_blocking_waits "sleep 8; gh run list --limit 3" "false"
assert_blocked "chained long sleep" "bash-9"

bash_check_blocking_waits "kubectl wait --for=condition=ready pod/api" "false"
assert_blocked "kubectl wait" "bash-9"

bash_check_blocking_waits "kubectl rollout status deploy/api -n prod" "false"
assert_blocked "kubectl rollout status" "bash-9"

bash_check_blocking_waits "docker wait mycontainer" "false"
assert_blocked "docker wait" "bash-9"

bash_check_blocking_waits "aws cloudformation wait stack-create-complete --stack-name s" "false"
assert_blocked "aws wait" "bash-9"

bash_check_blocking_waits "flux reconcile kustomization apps --with-source" "false"
assert_blocked "flux reconcile" "bash-9"

bash_check_blocking_waits "tail -f logs/app.log" "false"
assert_blocked "tail -f" "bash-9"

bash_check_blocking_waits "npm run dev" "false"
assert_blocked "dev server" "bash-9"

bash_check_blocking_waits "uvicorn app.main:app --reload" "false"
assert_blocked "uvicorn server" "bash-9"

suite "Foreground blocking waits — allowed"

bash_check_blocking_waits "gh run watch 31690698511 --exit-status" "true"
assert_allowed "gh run watch with run_in_background:true"

bash_check_blocking_waits 'until ! gh pr checks 351 | grep -q pending; do sleep 20; done' "true"
assert_allowed "poll loop backgrounded"

bash_check_blocking_waits "sleep 2 && curl -s localhost:3000/health" "false"
assert_allowed "short sleep under threshold"

bash_check_blocking_waits "sleep 0.5" "false"
assert_allowed "sub-second sleep"

bash_check_blocking_waits "gh pr checks 351" "false"
assert_allowed "one-shot gh pr checks"

bash_check_blocking_waits "gh run list --limit 5" "false"
assert_allowed "one-shot gh run list"

bash_check_blocking_waits "kubectl get pods -n prod" "false"
assert_allowed "read-only kubectl get"

bash_check_blocking_waits "tail -50 logs/app.log" "false"
assert_allowed "tail without -f"

bash_check_blocking_waits "npm run build" "false"
assert_allowed "npm run build"

bash_check_blocking_waits "npm test" "false"
assert_allowed "npm test"

bash_check_blocking_waits "docker ps -a" "false"
assert_allowed "docker ps"

suite "Timeout advisor"

assert_timeout "pytest gets test timeout" \
  "300000" "$(bash_suggest_timeout 'uv run pytest tests/ -q' '')"

assert_timeout "./tests/run-tests.sh gets test timeout" \
  "300000" "$(bash_suggest_timeout './tests/run-tests.sh' '')"

assert_timeout "cargo test gets test timeout" \
  "300000" "$(bash_suggest_timeout 'cargo test --all' '')"

assert_timeout "playwright gets browser timeout" \
  "480000" "$(bash_suggest_timeout 'npx playwright test 2>&1 | tail -25' '')"

assert_timeout "npm ci gets build timeout" \
  "600000" "$(bash_suggest_timeout 'npm ci' '')"

assert_timeout "uv sync gets build timeout" \
  "600000" "$(bash_suggest_timeout 'uv sync --all-extras' '')"

assert_timeout "docker build gets build timeout" \
  "600000" "$(bash_suggest_timeout 'docker build -t app .' '')"

assert_timeout "brew install gets build timeout" \
  "600000" "$(bash_suggest_timeout 'brew install jq' '')"

assert_timeout "explicit timeout is left alone" \
  "" "$(bash_suggest_timeout 'uv run pytest tests/' '60000')"

assert_timeout "over-ceiling timeout is clamped" \
  "600000" "$(bash_suggest_timeout 'uv run pytest tests/' '900000')"

assert_timeout "fast command gets no timeout" \
  "" "$(bash_suggest_timeout 'git status --short' '')"

assert_timeout "grep gets no timeout" \
  "" "$(bash_suggest_timeout 'grep -rn TODO src/' '')"

summary
