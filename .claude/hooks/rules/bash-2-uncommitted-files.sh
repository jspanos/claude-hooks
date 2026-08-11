# =============================================================================
# bash-2-uncommitted-files.sh — Rule: Protect files with uncommitted git changes
#
# Target extraction lives in lib/mutation-targets.sh (shared with bash-7), so
# this rule only decides policy: block when a destroyed path has uncommitted
# work that git could not recover.
#
# Covered operations: rm, unlink, shred, output-redirect (>), sed -i, perl -i,
# truncate, ed, ex, dd of=, tee, mv, cp, install, ln -f, rsync, scp, patch,
# git checkout/restore/clean -f/reset --hard — each also detected behind a
# `cd <dir> &&` prefix or later in a pipeline.
# =============================================================================

bash_check_uncommitted_files() {
  local cmd="$1"

  # Quick exit if not in a git repo
  git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1 || return 0

  extract_mutation_targets "$cmd"
  [[ -z "$MUT_OP_TYPE" ]] && return 0

  # ── Whole-tree operations: block if anything at all is uncommitted ────────
  if [[ -n "$MUT_WHOLE_TREE" ]]; then
    local dirty
    dirty="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | head -5)"
    if [[ -n "$dirty" ]]; then
      local count
      count="$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      deny_and_log "bash-2" \
        "$MUT_WHOLE_TREE, and $count file(s) currently have uncommitted changes:
$dirty

Commit or stash first ('git stash'), then re-run. If you only need to discard
specific files, name them explicitly instead of operating on the whole tree."
    fi
    return 0
  fi

  [[ ${#MUT_TARGETS[@]} -eq 0 ]] && return 0

  local target
  for target in "${MUT_TARGETS[@]}"; do
    # Only care about files inside the project
    [[ "$target" != "$PROJECT_DIR"/* && "$target" != "$PROJECT_DIR" ]] && continue

    local rel_path="${target#$PROJECT_DIR/}"
    [[ -z "$rel_path" || "$rel_path" == "$target" ]] && continue

    local git_status
    git_status="$(git -C "$PROJECT_DIR" status --porcelain -- "$rel_path" 2>/dev/null)"
    [[ -z "$git_status" ]] && continue

    local xy="${git_status:0:2}"
    local status_desc
    case "$xy" in
      " M"|"MM"|"AM") status_desc="unstaged modifications" ;;
      "M "|"MA")      status_desc="staged modifications" ;;
      "A ")           status_desc="new file staged (not yet committed)" ;;
      "R "|"RM")      status_desc="renamed (staged)" ;;
      "D "|" D")      status_desc="deletion staged or working-tree deleted" ;;
      "??")           status_desc="untracked new file (never committed)" ;;
      *)              status_desc="uncommitted changes (git status: '${xy}')" ;;
    esac

    deny_and_log "bash-2" \
      "'$rel_path' has $status_desc and would be affected by $MUT_OP_TYPE. Commit or stash your changes first ('git stash') before using shell commands to modify this file. For edits, prefer the Edit/Write tools which keep changes visible in git."
  done
}
