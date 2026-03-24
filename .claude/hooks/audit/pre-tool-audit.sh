#!/usr/bin/env bash
# =============================================================================
# pre-tool-audit.sh — Audit log entry for every PreToolUse event
#
# Fires on: PreToolUse (matcher: ".*" — all tools)
# Purpose:  Write an "intent" record before each tool execution.
#           Paired with post-tool-audit.sh which records the outcome.
#           tool_use_id links the two records together.
#
# Log: $PROJECT_DIR/.claude/logs/audit.jsonl (JSONL, one object per line)
# This hook is async so it never blocks Claude.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

HOOK_INPUT="$(read_stdin)"

TIMESTAMP="$(iso_timestamp)"
SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"
TOOL_NAME="$(get_field "$HOOK_INPUT" ".tool_name")"
TOOL_USE_ID="$(get_field "$HOOK_INPUT" ".tool_use_id")"
CWD="$(get_field "$HOOK_INPUT" ".cwd")"
PERMISSION_MODE="$(get_field "$HOOK_INPUT" ".permission_mode")"

# Embed tool_input as a proper JSON object, not an escaped string
TOOL_INPUT_JSON="$(printf '%s' "$HOOK_INPUT" | jq '.tool_input // {}')"

RECORD="$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg tool "$TOOL_NAME" \
  --arg tool_use_id "$TOOL_USE_ID" \
  --arg cwd "$CWD" \
  --arg permission_mode "$PERMISSION_MODE" \
  --argjson tool_input "$TOOL_INPUT_JSON" \
  '{
    timestamp: $ts,
    session_id: $session,
    event: "PreToolUse",
    tool_name: $tool,
    tool_use_id: $tool_use_id,
    cwd: $cwd,
    permission_mode: $permission_mode,
    tool_input: $tool_input,
    blocked: false
  }')"

write_audit_record "$RECORD"

exit 0
