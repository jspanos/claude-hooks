#!/usr/bin/env bash
# =============================================================================
# post-tool-audit.sh — Audit log entry for every PostToolUse event
#
# Fires on: PostToolUse (matcher: ".*" — all tools)
# Purpose:  Write an "outcome" record after each tool execution.
#           tool_use_id links this to the matching pre-tool-audit.sh record.
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

TOOL_INPUT_JSON="$(printf '%s' "$HOOK_INPUT" | jq '.tool_input // {}')"
TOOL_RESPONSE_JSON="$(printf '%s' "$HOOK_INPUT" | jq '.tool_response // {}')"
SUCCESS="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_response.success // true')"

RECORD="$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg tool "$TOOL_NAME" \
  --arg tool_use_id "$TOOL_USE_ID" \
  --arg cwd "$CWD" \
  --arg success "$SUCCESS" \
  --argjson tool_input "$TOOL_INPUT_JSON" \
  --argjson tool_response "$TOOL_RESPONSE_JSON" \
  '{
    timestamp: $ts,
    session_id: $session,
    event: "PostToolUse",
    tool_name: $tool,
    tool_use_id: $tool_use_id,
    cwd: $cwd,
    success: ($success == "true"),
    tool_input: $tool_input,
    tool_response: $tool_response
  }')"

write_audit_record "$RECORD"

exit 0
