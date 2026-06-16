#!/usr/bin/env bash
# =============================================================================
# post-tool-audit.sh — Audit record per PostToolUse (optimized)
#
# Optimization: build the entire JSONL record in a single jq pass that reads
# the raw hook payload from stdin (was: 4 separate jq forks).
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

TIMESTAMP="$(iso_timestamp)"

RECORD="$(jq -c --arg ts "$TIMESTAMP" '
  {
    timestamp: $ts,
    session_id: (.session_id // ""),
    event: "PostToolUse",
    tool_name: (.tool_name // ""),
    tool_use_id: (.tool_use_id // ""),
    cwd: (.cwd // ""),
    success: ((.tool_response.success // true) == true),
    tool_input: (.tool_input // {}),
    tool_response: (.tool_response // {})
  }')"

write_audit_record "$RECORD"
exit 0
