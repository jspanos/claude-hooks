# =============================================================================
# bash-7-protected-config.sh — Rule: Hooks may not be disabled from the shell
#
# Blocks shell commands that would delete, overwrite, move, or chmod the hook
# enforcement layer itself (.claude/hooks/, .claude/settings*.json, and the
# .claude-hooks-source marker).
#
# Reuses lib/mutation-targets.sh, so `cd .claude && rm settings.json` and
# `mv .claude/hooks /tmp/x` are caught alongside the direct forms.
#
# Exempt: the claude-hooks source repo itself (marked by .claude-hooks-source
# at its root), where editing these files is the entire point.
# =============================================================================

bash_check_protected_config() {
  local cmd="$1"

  hooks_source_repo && return 0

  extract_mutation_targets "$cmd"

  local -a all=()
  [[ ${#MUT_TARGETS[@]}      -gt 0 ]] && all+=("${MUT_TARGETS[@]}")
  [[ ${#MUT_META_TARGETS[@]} -gt 0 ]] && all+=("${MUT_META_TARGETS[@]}")
  [[ ${#all[@]} -eq 0 ]] && return 0

  local target desc
  for target in "${all[@]}"; do
    if desc="$(protected_path_match "$target")"; then
      deny_and_log "bash-7" \
        "Refusing $MUT_OP_TYPE on $desc: '$target'.

$(protected_paths_advice)"
    fi
  done
}
