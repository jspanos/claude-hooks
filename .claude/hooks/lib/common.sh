#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared utilities for all Claude Code hook scripts
#
# USAGE: Source this file from other hook scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"
# =============================================================================

# ---------------------------------------------------------------------------
# Resolve project dir: prefer CLAUDE_PROJECT_DIR, fall back to git root, then pwd
# ---------------------------------------------------------------------------
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# ---------------------------------------------------------------------------
# Guard: jq must be available
# ---------------------------------------------------------------------------
require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "[claude-hooks] ERROR: jq is not installed. Install with: brew install jq" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Read the full stdin payload into a variable.
# ---------------------------------------------------------------------------
read_stdin() {
  local payload
  payload="$(cat)"
  printf '%s' "$payload"
}

# ---------------------------------------------------------------------------
# Extract a field from hook JSON using jq.
# Usage: get_field "$HOOK_INPUT" ".tool_name"
# ---------------------------------------------------------------------------
get_field() {
  local json="$1"
  local path="$2"
  printf '%s' "$json" | jq -r "$path // empty"
}

# ---------------------------------------------------------------------------
# Audit log paths
# ---------------------------------------------------------------------------
audit_log_dir() {
  echo "${PROJECT_DIR}/.claude/logs"
}

audit_log_path() {
  echo "$(audit_log_dir)/audit.jsonl"
}

# ---------------------------------------------------------------------------
# Append a single JSONL record to the audit log.
# ---------------------------------------------------------------------------
write_audit_record() {
  local record="$1"
  local log_dir
  log_dir="$(audit_log_dir)"
  mkdir -p "$log_dir"
  printf '%s\n' "$record" >> "$(audit_log_path)"
}

# ---------------------------------------------------------------------------
# Emit a deny JSON response for PreToolUse and exit 0.
# Usage: deny_tool_use "Human-readable reason"
# ---------------------------------------------------------------------------
deny_tool_use() {
  local reason="$1"
  jq -n \
    --arg reason "$reason" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  exit 0
}

# ---------------------------------------------------------------------------
# ISO 8601 UTC timestamp
# ---------------------------------------------------------------------------
iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}
