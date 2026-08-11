# =============================================================================
# protected-paths.sh — Shared matcher for hook infrastructure paths
#
# The hook layer can only enforce rules while its own files are intact. Any
# agent able to rewrite a rule file, delete it, or edit settings.json can turn
# every other rule off in one step. This matcher marks those paths so both the
# Bash side (bash-7) and the file-tool side (file-2) can refuse to touch them.
#
# Escape hatch: a project that legitimately develops these hooks marks itself
# with a '.claude-hooks-source' file at its root. That marker is itself a
# protected path, so it cannot be created from inside a guarded project — and
# it sits outside .claude/hooks/, so deploy.sh never copies it to a target.
# =============================================================================

# ---------------------------------------------------------------------------
# True when the current project is the hooks source repo (self-edit allowed).
# ---------------------------------------------------------------------------
hooks_source_repo() {
  [[ -n "${PROJECT_DIR:-}" && -f "$PROJECT_DIR/.claude-hooks-source" ]]
}

# ---------------------------------------------------------------------------
# protected_path_match <path>
#   Echoes a human-readable description and returns 0 when the path is part of
#   the hook enforcement layer. Returns 1 otherwise.
#   Accepts absolute or relative paths; matching is on path *shape*, so it
#   covers project-local (.claude/...) and global (~/.claude/...) alike.
# ---------------------------------------------------------------------------
protected_path_match() {
  local p="$1"
  [[ -z "$p" ]] && return 1

  # Strip surrounding quotes that survived tokenization
  p="${p//\"/}"
  p="${p//\'/}"

  case "$p" in
    *.claude/hooks|*.claude/hooks/*)
      echo "hook scripts (.claude/hooks/)"; return 0 ;;
    *.claude/settings.json|*.claude/settings.local.json|*.claude/settings.global.json)
      echo "hook wiring (.claude/settings*.json)"; return 0 ;;
    *.claude-hooks-source)
      echo "the hooks self-edit marker (.claude-hooks-source)"; return 0 ;;
  esac

  # Bare relative forms, e.g. 'settings.json' used after 'cd .claude'
  case "$p" in
    .claude/hooks|.claude/hooks/*|.claude/settings*.json|.claude-hooks-source)
      echo "hook enforcement files"; return 0 ;;
  esac

  return 1
}

# ---------------------------------------------------------------------------
# protected_paths_advice — shared tail for both rules' deny messages.
# ---------------------------------------------------------------------------
protected_paths_advice() {
  cat <<'ADVICE'
These files are the enforcement layer itself — editing or deleting them
disables every other safety rule, so the hooks refuse to modify them from
inside a guarded project.

If you genuinely need to change the hooks:
  • Edit them in the claude-hooks source repo (the one containing
    '.claude-hooks-source' at its root), run ./tests/run-tests.sh, then
    redeploy with ./scripts/deploy.sh
  • Or have the user make the change directly, outside the agent session
ADVICE
}
