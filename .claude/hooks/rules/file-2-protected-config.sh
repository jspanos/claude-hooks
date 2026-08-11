# =============================================================================
# file-2-protected-config.sh — Rule: Write/Edit may not disable the hooks
#
# The file-tool counterpart to bash-7. Without this, an agent blocked from
# `rm .claude/hooks/rules/bash-5-pipe-abuse.sh` could simply Write an empty
# function over it and every downstream rule would silently stop firing.
#
# Exempt: the claude-hooks source repo itself (.claude-hooks-source marker).
# =============================================================================

file_check_protected_config() {
  local file_path="$1"

  hooks_source_repo && return 0

  local desc
  if desc="$(protected_path_match "$file_path")"; then
    deny_and_log "file-2" \
      "Refusing to write $desc: '$file_path'.

$(protected_paths_advice)"
  fi
}
