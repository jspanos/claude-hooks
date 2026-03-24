#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/pre-tool-use.sh — Unified PreToolUse Hook (dispatcher)
#
# Fires on: ALL PreToolUse events
#
# Responsibilities:
#   1. Log every tool call to .claude/logs/audit.jsonl
#   2. Apply Bash safety rules (sourced from rules/):
#        [bash-1] No absolute project/home paths — use relative paths
#        [bash-2] No deletion/modification of files with uncommitted git changes
#        [bash-3] SSH and kubectl must be read-only (no system modifications)
#        [bash-4] No inline scripts — use the scripts/ directory workflow
#        [bash-5] No pipe/redirect abuse (curl|bash, xargs rm, etc.)
#        [bash-6] Python must run in a venv; prefer uv for package management
#   3. Apply Write|Edit safety rules (sourced from rules/):
#        [file-1] No writes to sensitive files (.env, *.pem, credentials, etc.)
#
# All blocked events are written to the audit log with blocked=true + rule + reason.
# Each rule lives in its own file under .claude/hooks/rules/
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_jq

# ─── Parse input ─────────────────────────────────────────────────────────────

HOOK_INPUT="$(read_stdin)"
TOOL_NAME="$(get_field "$HOOK_INPUT" ".tool_name")"
TOOL_USE_ID="$(get_field "$HOOK_INPUT" ".tool_use_id")"
SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"
CWD="$(get_field "$HOOK_INPUT" ".cwd")"
TIMESTAMP="$(iso_timestamp)"

# Fallback: use project dir if cwd not supplied
[[ -z "$CWD" ]] && CWD="$PROJECT_DIR"

TOOL_INPUT_JSON="$(printf '%s' "$HOOK_INPUT" | jq '.tool_input // {}')"

# ─── Logging helpers ─────────────────────────────────────────────────────────

# Write one JSONL record. $1 = extra JSON fields to merge (default: {})
_log() {
  local extra="${1:-\{\}}"
  local record
  record="$(jq -cn \
    --arg ts        "$TIMESTAMP" \
    --arg session   "$SESSION_ID" \
    --arg tool      "$TOOL_NAME" \
    --arg tid       "$TOOL_USE_ID" \
    --arg cwd       "$CWD" \
    --argjson input "$TOOL_INPUT_JSON" \
    --argjson extra "$extra" \
    '{timestamp:$ts, session_id:$session, event:"PreToolUse",
      tool_name:$tool, tool_use_id:$tid, cwd:$cwd,
      tool_input:$input} + $extra')"
  write_audit_record "$record"
}

# Log intent at the top (may be superseded by a blocked log below)
_log '{"blocked":false}'

# Deny + log + exit. $1=rule-id  $2=human reason
deny_and_log() {
  local rule="$1"
  local reason="$2"
  _log "$(jq -cn --arg rule "$rule" --arg reason "$reason" \
    '{blocked:true, rule:$rule, reason:$reason}')"
  deny_tool_use "[$rule] $reason"
}

# ─── Source rule files ────────────────────────────────────────────────────────

for rule_file in "$SCRIPT_DIR/rules/"*.sh; do
  source "$rule_file"
done

# ─────────────────────────────────────────────────────────────────────────────
# Route to tool-specific checks
# ─────────────────────────────────────────────────────────────────────────────

case "$TOOL_NAME" in

  Bash)
    COMMAND="$(get_field "$HOOK_INPUT" ".tool_input.command")"
    [[ -z "$COMMAND" ]] && exit 0

    bash_check_absolute_paths    "$COMMAND"
    bash_check_uncommitted_files "$COMMAND"
    bash_check_remote_readonly   "$COMMAND"
    bash_check_inline_scripts    "$COMMAND"
    bash_check_pipe_abuse        "$COMMAND"
    bash_check_python_venv       "$COMMAND"
    ;;

  Write|Edit)
    FILE_PATH="$(get_field "$HOOK_INPUT" ".tool_input.file_path")"
    [[ -z "$FILE_PATH" ]] && exit 0
    file_check_sensitive_path "$FILE_PATH"
    ;;

esac

exit 0
