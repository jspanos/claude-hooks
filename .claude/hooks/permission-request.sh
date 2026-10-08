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
#             irreversible external state changes (force/protected-branch
#             git push, publish, deploy)
#
# Rules (by tool):
#   Read-only tools     → always ALLOW
#   Agent/task/plan ops → always ALLOW
#   Write|Edit          → DENY sensitive, ALLOW within project or any git work
#                         tree (non-ignored), DEFER elsewhere
#   Bash                → DENY dangerous patterns, DEFER external publishing,
#                         ALLOW everything else
#   Default             → ALLOW (pre-tool-use guards the real dangers)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git-push.sh"

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
  # Collapse ../ segments via the parent dir (when it exists)
  local parent
  if parent="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)"; then
    path="$parent/$(basename "$path")"
  fi
  # Unresolved ../ (parent missing) could escape any prefix match — reject
  [[ "$path" == *"/../"* || "$path" == *"/.." ]] && return 1

  [[ -n "$PROJECT_DIR" && "$path" == "$PROJECT_DIR"/* ]] && return 0

  # Extra trusted directories: CLAUDE_HOOKS_EXTRA_DIRS (colon-separated)
  local -a extra=()
  local IFS=':' dir
  # shellcheck disable=SC2206
  [[ -n "${CLAUDE_HOOKS_EXTRA_DIRS:-}" ]] && extra=(${CLAUDE_HOOKS_EXTRA_DIRS})
  for dir in "${extra[@]}"; do
    dir="${dir%/}"
    [[ -n "$dir" && "$path" == "$dir"/* ]] && return 0
  done
  return 1
}

# True if file path is a git-managed scratch/message file (e.g. COMMIT_MSG.tmp,
# COMMIT_EDITMSG, MERGE_MSG, TAG_EDITMSG, SQUASH_MSG) inside any repo's .git dir.
# These are throwaway commit-message buffers; writing them is always safe and
# routinely happens outside the current project (committing in another repo).
_is_git_commit_tmp() {
  local path="$1"
  printf '%s' "$path" | grep -qE '(^|/)\.git/([A-Z_]*MSG[A-Za-z._]*|COMMIT_EDITMSG)(\.tmp)?$'
}

# Absolute path with a symlinked final component resolved, so a link inside a
# trusted dir can't carry a write to its target elsewhere (e.g. repo/x -> ~/.zshrc)
_real_path() {
  local path="$1"
  [[ "$path" != /* ]] && path="$CWD/$path"
  if [[ -L "$path" ]]; then
    path="$(perl -MCwd=abs_path -e 'print abs_path(shift) // ""' "$path")"
  fi
  printf '%s' "$path"
}

# git in a repo we don't control: never run its fsmonitor hook
_git() {
  git -c core.fsmonitor=false -C "$@"
}

# True if file path is inside some git work tree and not git-ignored, so any
# edit is recoverable via git. Covers sibling repos without per-machine config.
_within_git_worktree() {
  local path="$1"
  [[ "$path" != /* ]] && path="$CWD/$path"
  # Never treat git internals as ordinary repo content
  [[ "$path" == *"/.git/"* || "$path" == *"/.git" ]] && return 1

  # Nearest existing ancestor (target file or its dirs may not exist yet)
  local dir
  dir="$(dirname "$path")"
  while [[ ! -d "$dir" && "$dir" != "/" ]]; do
    dir="$(dirname "$dir")"
  done
  dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  [[ "$dir" == "/" ]] && return 1

  [[ "$(_git "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || return 1

  # A repo rooted at $HOME or above (dotfiles) would cover shell rc files etc.
  local top home
  top="$(_git "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd "$top" && pwd -P)" || return 1
  home="$(cd "$HOME" 2>/dev/null && pwd -P)" || home="$HOME"
  [[ "$top" == "/" || "$home" == "$top" || "$home" == "$top"/* ]] && return 1
  # Agent config (hooks, settings) must never self-approve, versioned or not
  [[ "$dir" == "$home/.claude" || "$dir" == "$home/.claude/"* ]] && return 1

  # Ignored files (local config, build output) have no git history to restore from
  _git "$dir" check-ignore -q -- "$path" 2>/dev/null && return 1
  return 0
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

  # Mask safe git subcommands that share a name with destructive shell verbs.
  # 'git rm' stages a removal (reversible, repo-scoped) — it is not filesystem
  # 'rm -rf' and must not trip the recursive-deletion pattern below.
  # Only when git is the command word, and never if the command redefines git
  # (`git(){ rm "$@"; }; git rm -rf /` would otherwise hide a real rm -rf).
  if ! printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_-])git[[:space:]]*\([[:space:]]*\)|function[[:space:]]+git\b|alias[[:space:]]+git='; then
    cmd="$(printf '%s' "$cmd" | perl -pe 's/(^|[;&|(]\s*)git\s+rm\b/$1gitDEL/g')"
  fi

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

  # Git: force/delete/tag pushes and pushes to protected branches only —
  # a plain push of a feature branch is routine (see lib/git-push.sh)
  git_push_needs_review "$cmd" "$CWD" && return 0

  local -a DEFER_PATTERNS=(
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

  # ── Interactive UI tool: must pass through untouched ───────────────────────
  # Returning {behavior:allow} here makes the harness skip rendering the menu,
  # yielding empty answers. Exit with no JSON so default handling runs.
  AskUserQuestion)
    exit 0
    ;;

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
  SendMessage|TeamCreate|TeamDelete)
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

    # Judge the symlink target, not the link: that's where the write lands
    REAL_PATH="$(_real_path "$FILE_PATH")"
    [[ -z "$REAL_PATH" ]] && _defer "symlink target unresolvable — requires user confirmation"

    if _is_sensitive_path "$FILE_PATH" || _is_sensitive_path "$REAL_PATH"; then
      _deny "Write to sensitive file path '$FILE_PATH' is not permitted."
    fi

    if _is_git_commit_tmp "$REAL_PATH"; then
      _allow "git commit-message temp file"
    fi

    if _within_project "$REAL_PATH"; then
      _allow "non-sensitive project file"
    fi

    if _within_git_worktree "$REAL_PATH"; then
      _allow "non-sensitive file in git work tree (recoverable)"
    fi

    # Outside project and any git repo: defer to user
    _defer "file is outside project and git work trees — requires user confirmation"
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
