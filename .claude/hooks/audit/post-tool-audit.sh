#!/usr/bin/env bash
# =============================================================================
# post-tool-audit.sh — Audit record per PostToolUse (optimized)
#
# Optimization: build the entire JSONL record in a single jq pass that reads
# the raw hook payload from stdin (was: 4 separate jq forks).
#
# Also resolves duration_ms by looking back for this tool_use_id's PreToolUse
# record (which carries ts_ms). Second-resolution ISO stamps were too coarse to
# tell a 300ms call from a 1.4s one, and duration is the whole point of the
# wall-clock tuning work — without it, "why is this slow" needs a Pre/Post join.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

TIMESTAMP="$(iso_timestamp)"
TIMESTAMP_MS="$(epoch_ms)"

RECORD="$(jq -c --arg ts "$TIMESTAMP" --arg tsms "$TIMESTAMP_MS" '
  {
    timestamp: $ts,
    ts_ms: ($tsms|tonumber),
    session_id: (.session_id // ""),
    event: "PostToolUse",
    tool_name: (.tool_name // ""),
    tool_use_id: (.tool_use_id // ""),
    cwd: (.cwd // ""),
    success: ((.tool_response.success // true) == true),
    tool_input: (.tool_input // {}),
    tool_response: (.tool_response // {})
  }')"

# ── Attach duration by finding this call's PreToolUse record ────────────────
TOOL_USE_ID="$(printf '%s' "$RECORD" | jq -r '.tool_use_id')"
if [[ -n "$TOOL_USE_ID" ]]; then
  START_MS="$(tail -n 500 "$(audit_log_path)" 2>/dev/null \
    | grep -F "$TOOL_USE_ID" \
    | jq -R -r 'fromjson? // empty | select(.event=="PreToolUse") | .ts_ms // empty' \
    | tail -1)"
  if [[ -n "$START_MS" ]]; then
    RECORD="$(printf '%s' "$RECORD" \
      | jq -c --argjson d "$(( TIMESTAMP_MS - START_MS ))" '. + {duration_ms: $d}')"
  fi
fi

write_audit_record "$RECORD"
exit 0
