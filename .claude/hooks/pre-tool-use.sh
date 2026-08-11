#!/usr/bin/env bash
# =============================================================================
# pre-tool-use.sh — Unified PreToolUse Hook (dispatcher, optimized)
#
# Fires on every PreToolUse. Optimizations vs. previous version:
#   • Two jq forks total (scalars + tool_input) instead of 6+
#   • Rules only sourced when TOOL_NAME ∈ {Bash, Write, Edit}
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/protected-paths.sh"
source "$SCRIPT_DIR/lib/mutation-targets.sh"

require_jq

HOOK_INPUT="$(read_stdin)"
TIMESTAMP="$(iso_timestamp)"

# ─── Single jq call: emit all scalars as TSV ────────────────────────────────
IFS=$'\t' read -r TOOL_NAME TOOL_USE_ID SESSION_ID CWD < <(
  printf '%s' "$HOOK_INPUT" | jq -r '
    [ (.tool_name // "")
    , (.tool_use_id // "")
    , (.session_id // "")
    , (.cwd // "")
    ] | @tsv'
)
# Extract tool_input as compact JSON (single second jq fork)
TOOL_INPUT_JSON="$(printf '%s' "$HOOK_INPUT" | jq -c '.tool_input // {}')"

[[ -z "$CWD" ]] && CWD="$PROJECT_DIR"

# ─── Log helpers ────────────────────────────────────────────────────────────
_log() {
  local extra="${1:-\{\}}"
  local record
  record="$(jq -cn \
    --arg ts "$TIMESTAMP" --arg session "$SESSION_ID" \
    --arg tool "$TOOL_NAME" --arg tid "$TOOL_USE_ID" \
    --arg cwd "$CWD" \
    --argjson input "$TOOL_INPUT_JSON" \
    --argjson extra "$extra" \
    '{timestamp:$ts, session_id:$session, event:"PreToolUse",
      tool_name:$tool, tool_use_id:$tid, cwd:$cwd,
      tool_input:$input} + $extra')"
  write_audit_record "$record"
}
_log '{"blocked":false}'

deny_and_log() {
  local rule="$1" reason="$2"
  _log "$(jq -cn --arg rule "$rule" --arg reason "$reason" \
    '{blocked:true, rule:$rule, reason:$reason}')"
  deny_tool_use "[$rule] $reason"
}

# ─── Apply file rules to a path (shared by the file-tool + catch-all arms) ──
run_file_rules() {
  local path="$1"
  [[ -z "$path" ]] && return 0
  for rule_file in "$SCRIPT_DIR/rules/"file-*.sh; do
    source "$rule_file"
  done
  file_check_sensitive_path   "$path"
  file_check_protected_config "$path"
}

# ─── Source rules ONLY for tools that need them ─────────────────────────────
case "$TOOL_NAME" in
  Bash)
    for rule_file in "$SCRIPT_DIR/rules/"bash-*.sh; do
      source "$rule_file"
    done
    COMMAND="$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '.command // ""')"
    [[ -z "$COMMAND" ]] && exit 0
    bash_check_absolute_paths        "$COMMAND"
    bash_check_uncommitted_files     "$COMMAND"
    bash_check_remote_readonly       "$COMMAND"
    bash_check_inline_scripts        "$COMMAND"
    bash_check_pipe_abuse            "$COMMAND"
    bash_check_python_venv           "$COMMAND"
    bash_check_protected_config      "$COMMAND"
    bash_check_interpreter_file_ops  "$COMMAND"
    ;;
  Write|Edit|NotebookEdit)
    FILE_PATH="$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '.file_path // .notebook_path // ""')"
    run_file_rules "$FILE_PATH"
    ;;
  *)
    # Catch-all: MCP servers and future built-ins also write files, and used to
    # skip every rule because the case above only named three tools. Apply the
    # file rules to any tool that both names a path and looks like a writer —
    # either by tool name or by carrying a content-ish payload. Read-only tools
    # (Read/Grep/Glob) match neither test and fall through untouched.
    CANDIDATE_PATH="$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '
      .file_path // .notebook_path // .target_file // .filePath // .path // ""')"
    [[ -z "$CANDIDATE_PATH" ]] && exit 0

    HAS_CONTENT="$(printf '%s' "$TOOL_INPUT_JSON" | jq -r '
      if (has("content") or has("new_string") or has("new_str") or has("edits")
          or has("new_source") or has("contents") or has("text") or has("data"))
      then "yes" else "no" end')"

    if [[ "$HAS_CONTENT" == "yes" ]] || \
       printf '%s' "$TOOL_NAME" | grep -qiE 'write|edit|create|update|delete|remove|move|rename|save|patch|append'; then
      run_file_rules "$CANDIDATE_PATH"
    fi
    ;;
esac

exit 0
