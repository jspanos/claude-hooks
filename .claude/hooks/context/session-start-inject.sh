#!/usr/bin/env bash
# =============================================================================
# session-start-inject.sh — Inject project context at session start
#
# Fires on: SessionStart (all sources: startup, resume, compact, clear)
# Purpose:  Re-inject project context into Claude's working memory every time
#           a session begins or resumes — especially important after compaction,
#           where context may be significantly reduced.
#
# Context source: $PROJECT_DIR/context/project-context.md
# Output: JSON with additionalContext populated from that file.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

HOOK_INPUT="$(read_stdin)"
SESSION_SOURCE="$(get_field "$HOOK_INPUT" ".source")"
SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"

CONTEXT_FILE="${PROJECT_DIR}/context/project-context.md"

if [[ ! -f "$CONTEXT_FILE" ]]; then
  echo "[claude-hooks] WARNING: context file not found at ${CONTEXT_FILE}" >&2
  exit 0
fi

CONTEXT_CONTENT="$(cat "$CONTEXT_FILE")"
[[ -z "$CONTEXT_CONTENT" ]] && exit 0

# Build preamble based on what triggered the session start
case "$SESSION_SOURCE" in
  compact)
    PREAMBLE="[Context re-injected after conversation compaction]"
    ;;
  resume)
    PREAMBLE="[Session resumed — project context:]"
    ;;
  startup)
    PREAMBLE="[New session started — project context:]"
    ;;
  *)
    PREAMBLE="[Project context:]"
    ;;
esac

FULL_CONTEXT="${PREAMBLE}

${CONTEXT_CONTENT}"

# Log the injection
TIMESTAMP="$(iso_timestamp)"
RECORD="$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg source "$SESSION_SOURCE" \
  '{
    timestamp: $ts,
    session_id: $session,
    event: "SessionStart",
    context_injected: true,
    source: $source
  }')"
write_audit_record "$RECORD"

# Return context to Claude
jq -n \
  --arg context "$FULL_CONTEXT" \
  '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $context
    }
  }'

exit 0
