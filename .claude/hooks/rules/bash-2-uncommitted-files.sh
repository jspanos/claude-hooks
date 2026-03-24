# =============================================================================
# bash-2-uncommitted-files.sh — Rule: Protect files with uncommitted git changes
#
# Detect commands that could delete or destructively overwrite files, extract
# the target path(s), and check git status. Block if the target has uncommitted
# changes (modified, staged, or untracked) to prevent permanent data loss.
#
# Covered operations: rm, unlink, output-redirect (>), sed -i, perl -i,
# truncate, dd of=, tee, mv (source)
# =============================================================================

bash_check_uncommitted_files() {
  local cmd="$1"

  # Quick exit if not in a git repo
  git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1 || return 0

  local op_type=""
  local -a targets=()

  # ── rm / unlink ─────────────────────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*(rm|unlink)\s'; then
    op_type="deletion"
    local args
    args="$(printf '%s' "$cmd" | sed 's/^\s*\(rm\|unlink\)\s\+//')"
    while IFS= read -r tok; do
      [[ -n "$tok" && "$tok" != -* ]] && targets+=("$tok")
    done < <(printf '%s' "$args" | tr ' ' '\n' | grep -v '^-' | grep -v '^$')
  fi

  # ── Truncating output redirect: cmd > file  (but NOT >>  and NOT /dev/null) ─
  if printf '%s' "$cmd" | grep -qE '[^>]>[^>=]'; then
    op_type="${op_type:-overwrite}"
    while IFS= read -r t; do
      t="$(printf '%s' "$t" | sed 's/^[[:space:]]*//')"
      [[ -n "$t" && "$t" != "/dev/null" && "$t" != "-" ]] && targets+=("$t")
    done < <(printf '%s' "$cmd" | \
      perl -ne 'while (m{(?<![>])>(?![>=])\s*([^\s|&;]+)}g) { print "$1\n" }')
  fi

  # ── sed -i / perl -i (in-place edit) ────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\b(sed|perl)\s+(-i|--in-place)'; then
    op_type="${op_type:-in-place edit}"
    # Last non-flag token is typically the target file
    local last_arg
    last_arg="$(printf '%s' "$cmd" | awk '{print $NF}')"
    [[ -n "$last_arg" && "$last_arg" != -* ]] && targets+=("$last_arg")
  fi

  # ── truncate ────────────────────────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*truncate\s'; then
    op_type="${op_type:-truncate}"
    local trunc_target
    trunc_target="$(printf '%s' "$cmd" | awk '{print $NF}')"
    [[ -n "$trunc_target" && "$trunc_target" != -* ]] && targets+=("$trunc_target")
  fi

  # ── dd of=file ───────────────────────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\bdd\b.*\bof='; then
    op_type="${op_type:-dd overwrite}"
    local dd_target
    dd_target="$(printf '%s' "$cmd" | grep -oE 'of=[^[:space:]]+' | sed 's/^of=//')"
    [[ -n "$dd_target" ]] && targets+=("$dd_target")
  fi

  # ── tee (overwrites by default unless -a) ───────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\btee\b' && ! printf '%s' "$cmd" | grep -qE '\btee\s+-a'; then
    op_type="${op_type:-tee overwrite}"
    local tee_target
    tee_target="$(printf '%s' "$cmd" | grep -oE '\btee\s+[^[:space:]|&;]+' | awk '{print $2}')"
    [[ -n "$tee_target" ]] && targets+=("$tee_target")
  fi

  # ── mv (source file ceases to exist) ────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*mv\s'; then
    op_type="${op_type:-move}"
    local mv_src
    mv_src="$(printf '%s' "$cmd" | sed 's/^\s*mv\s\+//' | awk '{print $1}')"
    [[ -n "$mv_src" && "$mv_src" != -* ]] && targets+=("$mv_src")
  fi

  [[ ${#targets[@]} -eq 0 ]] && return 0

  for target in "${targets[@]}"; do
    # Skip shell globs — can't resolve at hook time
    [[ "$target" == *'*'* || "$target" == *'?'* || "$target" == *'['* ]] && continue
    # Skip variables that need expansion
    [[ "$target" == '$'* ]] && continue

    # Resolve to absolute path
    local abs_path
    if [[ "$target" == /* ]]; then
      abs_path="$target"
    else
      abs_path="$CWD/$target"
    fi

    # Only care about files inside the project
    [[ "$abs_path" != "$PROJECT_DIR"/* && "$abs_path" != "$PROJECT_DIR" ]] && continue

    # Get path relative to project root for git
    local rel_path="${abs_path#$PROJECT_DIR/}"
    [[ -z "$rel_path" ]] && continue

    # Query git status for this specific path
    local git_status
    git_status="$(git -C "$PROJECT_DIR" status --porcelain -- "$rel_path" 2>/dev/null)"
    [[ -z "$git_status" ]] && continue

    # Decode status flags
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
      "'$rel_path' has $status_desc and would be affected by $op_type. Commit or stash your changes first ('git stash') before using shell commands to modify this file. For edits, prefer the Edit/Write tools which keep changes visible in git."
  done
}
