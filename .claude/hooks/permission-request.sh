#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/permission-request.sh — Unified PermissionRequest Hook
#
# Philosophy: maximum agent autonomy with minimal interruption.
#
# Decision logic:
#   ALLOW  — safe, project-local operations; agent flows without prompting
#   DENY   — dangerous patterns (belt+suspenders with pre-tool-use)
#   DEFER  — exit 0, no output; shows user the permission dialog ONLY for
#             irreversible external state changes (git push, publish, deploy)
#
# Rules (by tool):
#   Read-only tools     → always ALLOW
#   Agent/task/plan ops → always ALLOW
#   Write|Edit          → ALLOW within project (non-sensitive), DENY sensitive,
#                         DEFER outside project
#   Bash                → DENY dangerous patterns, DEFER external publishing,
#                         ALLOW everything else
#   Default             → ALLOW (pre-tool-use guards the real dangers)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_jq

# ─── Parse input ─────────────────────────────────────────────────────────────

HOOK_INPUT="$(read_stdin)"
TOOL_NAME="$(get_field "$HOOK_INPUT" ".tool_name")"
SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"
CWD="$(get_field "$HOOK_INPUT" ".cwd")"
TIMESTAMP="$(iso_timestamp)"

[[ -z "$CWD" ]] && CWD="$PROJECT_DIR"

# ─── Logging ─────────────────────────────────────────────────────────────────

TOOL_INPUT_JSON="$(printf '%s' "$HOOK_INPUT" | jq '.tool_input // {}')"

_log_decision() {
  local decision="$1" reason="$2"
  local record
  record="$(jq -cn \
    --arg ts        "$TIMESTAMP" \
    --arg session   "$SESSION_ID" \
    --arg tool      "$TOOL_NAME" \
    --arg cwd       "$CWD" \
    --arg decision  "$decision" \
    --arg reason    "$reason" \
    --argjson input "$TOOL_INPUT_JSON" \
    '{timestamp:$ts, session_id:$session, event:"PermissionRequest",
      tool_name:$tool, cwd:$cwd, tool_input:$input,
      decision:$decision, reason:$reason}')"
  write_audit_record "$record"
}

# ─── Decision helpers ─────────────────────────────────────────────────────────

# Auto-approve: agent proceeds without user prompt
_allow() {
  local reason="${1:-auto-approved}"
  _log_decision "allow" "$reason"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "allow" }
    }
  }'
  exit 0
}

# Hard block: agent cannot proceed (pre-tool-use will also catch these)
_deny() {
  local reason="${1:-blocked by policy}"
  _log_decision "deny" "$reason"
  jq -n --arg msg "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "deny", message: $msg }
    }
  }'
  exit 0
}

# Defer: show user the normal permission dialog
# Used only for irreversible external state changes
_defer() {
  local reason="${1:-requires user confirmation}"
  _log_decision "defer" "$reason"
  exit 0  # No JSON output = Claude shows user the dialog
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# True if file path is within the project directory
_within_project() {
  local path="$1"
  # Resolve relative paths relative to CWD
  if [[ "$path" != /* ]]; then
    path="$CWD/$path"
  fi
  [[ -n "$PROJECT_DIR" && "$path" == "$PROJECT_DIR"/* ]]
}

# True if file path matches a sensitive pattern
_is_sensitive_path() {
  local path="$1"
  local -a SENSITIVE=(
    '(^|/)\.env(\.[a-zA-Z]+)?$'
    '\.(pem|key|p12|pfx|crt|cer|der)$'
    '(^|/)\.ssh/'
    '(secret|credential|password|passwd|token|apikey|api_key)(s)?\.(json|yaml|yml|toml|ini|conf|txt)$'
    '(^|/)\.(aws|gcp|azure)/(credentials|config|key)$'
    '\.(gpg|pgp|asc|keychain|keychain-db|kdbx|kdb)$'
    '(^|/)\.(netrc|npmrc|pypirc|gitcredentials)$'
    'terraform\.tfstate(\.backup)?$'
    '(^|/)\.kube/config$'
    '(^|/)\.docker/config\.json$'
  )
  for pat in "${SENSITIVE[@]}"; do
    printf '%s' "$path" | grep -qiE "$pat" && return 0
  done
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# BASH: Dangerous patterns → DENY (belt+suspenders with pre-tool-use)
# ─────────────────────────────────────────────────────────────────────────────
_bash_is_dangerous() {
  local cmd="$1"

  local -a DENY_PATTERNS=(
    # Recursive force deletion
    'rm\s+(-[^\s]*[rR][^\s]*[fF]|-[^\s]*[fF][^\s]*[rR]|-rf|-fr)'
    # Remote code execution via pipe
    '(curl|wget)\b.*\|[^|]*\b(bash|sh|python[23]?|node|perl)\b'
    # Obfuscated execution
    'base64\b.*-d\b.*\|[^|]*\b(bash|sh|python|node|eval)\b'
    '\|[[:space:]]*(sudo|su)\b'
    '\|[[:space:]]*eval\b'
    '\$\((curl|wget)\b'
    # Bulk destructive
    '\|[^|]*xargs[^|]*\brm\b'
    '\bfind\b.+(-exec[[:space:]]+rm\b|-delete\b)'
    # Writes to system paths
    '>+[[:space:]]*/([^[:space:]]*(etc|usr|bin|sbin|lib|boot|sys)/)'
    # Fork bomb
    ':\s*\(\s*\)\s*\{'
    # dd to raw disk
    'dd\b.*of=/dev/(sd[a-z]|nvme[0-9]|disk[0-9])[^p]'
  )

  for pat in "${DENY_PATTERNS[@]}"; do
    printf '%s' "$cmd" | grep -qE "$pat" && return 0
  done
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# BASH: External state changes → DEFER (require human confirmation)
#
# These are irreversible actions affecting external systems. The agent should
# not do these without explicit human sign-off.
# ─────────────────────────────────────────────────────────────────────────────
_bash_is_external_publish() {
  local cmd="$1"

  local -a DEFER_PATTERNS=(
    # Git: push to remote (any remote, any branch, except dry-run)
    '^\s*git\b.*\bpush\b(?!.*--dry-run)'
    # Package publishing
    '^\s*npm\s+(publish|unpublish)\b'
    '^\s*(yarn|pnpm)\s+publish\b'
    '^\s*twine\s+upload\b'
    '^\s*cargo\s+publish\b'
    '^\s*gem\s+push\b'
    '^\s*poetry\s+publish\b'
    # Container registries
    '^\s*docker\s+(push|login)\b'
    '^\s*podman\s+push\b'
    # Cloud platform deployments
    '^\s*heroku\b'
    '^\s*gcloud\b.*(deploy|publish|push)\b'
    '^\s*aws\b.*(deploy|cloudformation\s+deploy|s3\s+(sync|cp|mv)\b.*s3://)'
    '^\s*vercel\b'
    '^\s*netlify\b.*(deploy)\b'
    '^\s*fly\s+(deploy|launch)\b'
    '^\s*wrangler\s+(deploy|publish)\b'
    '^\s*railway\b.*(up|deploy)\b'
    '^\s*render\b.*(deploy)\b'
    # Infrastructure changes
    '^\s*(terraform|tofu|opentofu)\s+(apply|destroy|import|state\s+(mv|rm|push))\b'
    '^\s*pulumi\s+(up|destroy|import)\b'
    '^\s*ansible-playbook\b'
    # Database migrations in production
    '^\s*(alembic|flyway|liquibase)\b.*(upgrade|migrate)\b'
  )

  for pat in "${DEFER_PATTERNS[@]}"; do
    printf '%s' "$cmd" | perl -ne "exit(m{$pat}i ? 0 : 1)" 2>/dev/null && return 0
  done
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Route by tool
# ─────────────────────────────────────────────────────────────────────────────

case "$TOOL_NAME" in

  # ── Read-only tools: no risk, always allow ─────────────────────────────────
  Glob|Grep|Read|LS|NotebookRead|LSP)
    _allow "read-only tool"
    ;;

  # ── Web fetch/search: allow (pre-tool-use doesn't restrict these) ──────────
  WebFetch|WebSearch)
    _allow "web operation"
    ;;

  # ── Agent / task management: allow ────────────────────────────────────────
  Agent|TaskCreate|TaskUpdate|TaskGet|TaskList|TaskOutput|TaskStop|\
  SendMessage|AskUserQuestion|TeamCreate|TeamDelete)
    _allow "agent/task operation"
    ;;

  # ── Plan mode and worktrees: allow ────────────────────────────────────────
  ExitPlanMode|EnterPlanMode|EnterWorktree|ExitWorktree)
    _allow "planning operation"
    ;;

  # ── TodoWrite: project-local state, always allow ──────────────────────────
  TodoWrite)
    _allow "todo/task tracking"
    ;;

  # ── Bash: deny dangerous → defer external publishing → allow rest ──────────
  Bash)
    COMMAND="$(get_field "$HOOK_INPUT" ".tool_input.command")"
    [[ -z "$COMMAND" ]] && _allow "empty command"

    if _bash_is_dangerous "$COMMAND"; then
      _deny "Command matches a dangerous pattern and is not permitted. See pre-tool-use rules for details."
    fi

    if _bash_is_external_publish "$COMMAND"; then
      _defer "external state change — requires human confirmation"
    fi

    # Everything else: allow. Pre-tool-use handles the detailed rule enforcement.
    _allow "bash — no external publish or dangerous pattern detected"
    ;;

  # ── Write / Edit / NotebookEdit ────────────────────────────────────────────
  Write|Edit|NotebookEdit)
    FILE_PATH="$(get_field "$HOOK_INPUT" ".tool_input.file_path")"
    [[ -z "$FILE_PATH" ]] && _allow "no file path"

    if _is_sensitive_path "$FILE_PATH"; then
      _deny "Write to sensitive file path '$FILE_PATH' is not permitted."
    fi

    if _within_project "$FILE_PATH"; then
      _allow "non-sensitive project file"
    fi

    # Outside project directory: defer to user
    _defer "file is outside project directory — requires user confirmation"
    ;;

  # ── MCP tools: allow (they have their own access control) ─────────────────
  mcp__*)
    _allow "MCP tool"
    ;;

  # ── Cron / scheduling tools ────────────────────────────────────────────────
  CronCreate|CronDelete|CronList)
    _allow "cron operation"
    ;;

  # ── Default: allow — trust pre-tool-use for enforcement ───────────────────
  *)
    _allow "default — unknown tool, pre-tool-use provides enforcement"
    ;;

esac

exit 0
