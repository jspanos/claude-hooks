#!/usr/bin/env bash
# =============================================================================
# assert.sh — Test harness for Claude Code hook rules
#
# Usage: source this file in each test file BEFORE sourcing the rule under test.
# It mocks deny_and_log / deny_tool_use so rules can run without exiting.
# =============================================================================

# ── Test counters ─────────────────────────────────────────────────────────────
PASS=0
FAIL=0
_CURRENT_SUITE=""

# ── State set by rule calls ───────────────────────────────────────────────────
_BLOCKED=""
_BLOCK_RULE=""
_BLOCK_REASON=""

# ── Mock functions (override real ones from common.sh) ────────────────────────

# Override deny_tool_use — capture instead of exiting
deny_tool_use() {
  _BLOCKED="true"
  _BLOCK_REASON="${_BLOCK_REASON:-$1}"
}

# Override deny_and_log — capture rule + reason, do NOT call write_audit_record
deny_and_log() {
  _BLOCK_RULE="$1"
  _BLOCK_REASON="$2"
  _BLOCKED="true"
}

# Override write_audit_record — no-op in tests
write_audit_record() { :; }

# ── Helpers ───────────────────────────────────────────────────────────────────

_reset() {
  _BLOCKED=""
  _BLOCK_RULE=""
  _BLOCK_REASON=""
}

suite() {
  _CURRENT_SUITE="$1"
  echo ""
  echo "  $1"
}

assert_allowed() {
  local desc="$1"
  if [[ -z "$_BLOCKED" ]]; then
    printf "    \033[32m✓\033[0m %s\n" "$desc"
    PASS=$((PASS+1))
  else
    printf "    \033[31m✗\033[0m %s\n" "$desc"
    printf "      expected: allowed\n"
    printf "      got:      blocked by [%s] %s\n" "$_BLOCK_RULE" "$_BLOCK_REASON"
    FAIL=$((FAIL+1))
  fi
  _reset
}

assert_blocked() {
  local desc="$1"
  local expected_rule="${2:-}"
  if [[ -n "$_BLOCKED" ]]; then
    if [[ -z "$expected_rule" || "$_BLOCK_RULE" == "$expected_rule" ]]; then
      printf "    \033[32m✓\033[0m %s\n" "$desc"
      PASS=$((PASS+1))
    else
      printf "    \033[31m✗\033[0m %s\n" "$desc"
      printf "      expected: blocked by [%s]\n" "$expected_rule"
      printf "      got:      blocked by [%s] %s\n" "$_BLOCK_RULE" "$_BLOCK_REASON"
      FAIL=$((FAIL+1))
    fi
  else
    printf "    \033[31m✗\033[0m %s\n" "$desc"
    printf "      expected: blocked\n"
    printf "      got:      allowed\n"
    FAIL=$((FAIL+1))
  fi
  _reset
}

summary() {
  echo ""
  echo "-----------------------------------------"
  local total=$((PASS+FAIL))
  if [[ $FAIL -eq 0 ]]; then
    printf "\033[32m  All %d tests passed\033[0m\n" "$total"
  else
    printf "\033[31m  %d/%d tests failed\033[0m\n" "$FAIL" "$total"
  fi
  echo "-----------------------------------------"
  [[ $FAIL -eq 0 ]]
}
