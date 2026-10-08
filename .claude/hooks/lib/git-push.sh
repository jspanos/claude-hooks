# =============================================================================
# git-push.sh — Classify a `git push`: routine branch push vs. needs a human
#
# Used by permission-request.sh. Pushing a feature branch is routine and
# reversible; these are not, so they still go to the user:
#   • force pushes (--force*, -f, +refspec), --mirror, --all, --prune
#   • ref deletion (--delete, -d, :ref) and tag pushes (--tags,
#     --follow-tags, refs/tags/*, a name that is a local tag)
#   • any update to a protected branch: main, master, trunk, develop,
#     prod(uction), stable, release*, or the remote's default branch
#   • an implicit push whose target branch cannot be resolved, or whose
#     remote has push refspecs / mirror configured
#   • anything the parser cannot fully model (fail closed): wrappers,
#     expansions, escapes, `git -c`, and git aliases that may run push
#
# A false "defer" costs one prompt; a false "allow" skips the human, so every
# ambiguity resolves to defer.
#
# Usage: git_push_needs_review "$COMMAND" "$CWD"
#   returns 0 → defer to the user; 1 → no push needs review
# =============================================================================

GIT_PUSH_PROTECTED_RE='^(main|master|trunk|develop|prod|production|stable|release([/-].*)?)$'

_gp_git() {
  local dir="$1"; shift
  git -C "$dir" "$@" 2>/dev/null
}

_gp_resolve_dir() {
  local base="$1" target="$2"
  target="${target/#\~/$HOME}"
  [[ "$target" == /* ]] && printf '%s' "$target" || printf '%s' "$base/$target"
}

# True if pushing BRANCH to REMOTE would update a protected branch.
_gp_is_protected() {
  local dir="$1" remote="${2:-origin}" branch="$3"
  [[ "$branch" =~ $GIT_PUSH_PROTECTED_RE ]] && return 0
  local default
  default="$(_gp_git "$dir" symbolic-ref --short "refs/remotes/$remote/HEAD")"
  default="${default#"$remote"/}"
  [[ -n "$default" && "$branch" == "$default" ]]
}

# Remote branch an argument-less `git push` would update (empty if unknown).
_gp_implicit_target() {
  local dir="$1" target
  target="$(_gp_git "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{push}')"
  if [[ -n "$target" ]]; then
    printf '%s' "${target#*/}"
  else
    _gp_git "$dir" symbolic-ref --short -q HEAD
  fi
}

# Review the arguments following `push`. Returns 0 if review is needed.
_gp_args_need_review() {
  local dir="$1"; shift
  local -a pos=()

  while (( $# )); do
    case "$1" in
      --dry-run) return 1 ;;
      --force|--force-with-lease*|--force-if-includes|--mirror|--all|--branches|\
      --delete|--tags|--follow-tags|--prune)
        return 0 ;;
      --repo|--push-option|--receive-pack|--exec|-o) shift ;;
      --*) ;;
      *'>'|*'<') shift ;;               # bare redirect operator: skip its target
      *'>'*|*'<'*) ;;                   # 2>&1, >/dev/null
      -*)
        [[ "$1" == *n* ]] && return 1   # -n is --dry-run
        [[ "$1" == *[fd]* ]] && return 0
        ;;
      *) pos+=("$1") ;;
    esac
    shift
  done

  local remote="${pos[0]:-origin}"
  local -a refspecs=("${pos[@]:1}")

  [[ "$(_gp_git "$dir" config --bool "remote.$remote.mirror")" == true ]] && return 0

  if (( ${#refspecs[@]} == 0 )); then
    # Configured push refspecs decide the target, not the current branch.
    [[ -n "$(_gp_git "$dir" config --get-all "remote.$remote.push")" ]] && return 0
    # An earlier checkout/switch in the same command makes HEAD unknowable here.
    [[ -n "${_GP_SWITCHED:-}" ]] && return 0
    local target
    target="$(_gp_implicit_target "$dir")"
    [[ -z "$target" ]] && return 0
    _gp_is_protected "$dir" "$remote" "$target"
    return
  fi

  local r src dst
  for r in "${refspecs[@]}"; do
    [[ "$r" == +* ]] && return 0
    if [[ "$r" == *:* ]]; then
      src="${r%%:*}" dst="${r#*:}"
      [[ -z "$src" || -z "$dst" ]] && return 0
    else
      src="$r" dst="$r"
      # A bare name that is a local tag (and not a branch) pushes the tag.
      if _gp_git "$dir" show-ref -q --verify "refs/tags/$src" \
         && ! _gp_git "$dir" show-ref -q --verify "refs/heads/$src"; then
        return 0
      fi
    fi
    [[ "$src" == refs/tags/* || "$dst" == refs/tags/* ]] && return 0
    if [[ "$dst" == HEAD || "$dst" == @ ]]; then
      dst="$(_gp_git "$dir" symbolic-ref --short -q HEAD)"
      [[ -z "$dst" ]] && return 0
    fi
    dst="${dst#refs/heads/}"
    _gp_is_protected "$dir" "$remote" "$dst" && return 0
  done
  return 1
}

git_push_needs_review() {
  local cmd="$1" dir="${2:-$PWD}"
  local seg i gdir
  local -a w
  _GP_SWITCHED=""

  # Fail closed: this parser is a word splitter, not a shell. Anything it
  # cannot model in a segment that mentions both git and push is deferred:
  # wrappers (env, command, sudo, xargs, sh -c, VAR=x prefixes, subshells),
  # expansions/escapes ($ ` \ ( ) { }), git -c overrides, shell aliases.
  local mentions

  # Split into simple commands on ; & && || | and newlines, tracking `cd`.
  # fd redirects (2>&1, >&2, &>) are blanked first so '&' splits cleanly.
  while IFS= read -r seg; do
    mentions=""
    [[ "$seg" =~ (^|[^[:alnum:]_-])git([^[:alnum:]_-]|$) \
       && "$seg" =~ (^|[^[:alnum:]_-])push([^[:alnum:]_-]|$) ]] && mentions=1
    if [[ -n "$mentions" && "$seg" =~ [\$\`\\\(\)\{\}] ]]; then
      return 0
    fi

    read -ra w <<< "$seg"
    (( ${#w[@]} == 0 )) && continue
    for i in "${!w[@]}"; do w[i]="${w[i]//[\"\']/}"; done

    if [[ "${w[0]}" == cd ]]; then
      dir="$(_gp_resolve_dir "$dir" "${w[1]:-$HOME}")"
      continue
    fi
    if [[ "${w[0]}" != git ]]; then
      [[ -n "$mentions" ]] && return 0
      continue
    fi

    # Skip git's global options up to the subcommand.
    i=1 gdir="$dir"
    while (( i < ${#w[@]} )); do
      case "${w[i]}" in
        -C) gdir="$(_gp_resolve_dir "$dir" "${w[i+1]:-.}")"; i=$((i+2)) ;;
        -c|-c*|--config-env*)
          [[ -n "$mentions" ]] && return 0
          [[ "${w[i]}" == -c ]] && i=$((i+2)) || i=$((i+1)) ;;
        --git-dir|--work-tree|--namespace) i=$((i+2)) ;;
        -*) i=$((i+1)) ;;
        *) break ;;
      esac
    done
    case "${w[i]:-}" in
      checkout|switch) _GP_SWITCHED=1; continue ;;
      push) ;;
      *)
        # A git alias may expand to push (or to anything, if it is '!shell').
        local alias_val
        alias_val="$(_gp_git "$gdir" config --get "alias.${w[i]:-}")"
        if [[ -n "$alias_val" ]] \
           && [[ "$alias_val" == '!'* || "$alias_val" =~ (^|[[:space:]])push([[:space:]]|$) ]]; then
          return 0
        fi
        continue ;;
    esac

    _gp_args_need_review "$gdir" "${w[@]:i+1}" && return 0
  done < <(printf '%s\n' "$cmd" \
    | perl -pe 's/\d*>&\d*-?/ /g; s/&>>?/ /g; s/\|\||&&|[;|&]/\n/g')

  return 1
}
