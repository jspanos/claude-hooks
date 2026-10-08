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
#   • a destination that is not an already-configured remote (URL, path),
#     --repo / --receive-pack / --exec, glob refspecs, non-heads refs
#   • any push after a git command that may change HEAD, refs, aliases,
#     remotes or config earlier in the same line (checkout, tag, config, …),
#     or after pushd/popd/cd - (repo unknown)
#   • anything the parser cannot fully model (fail closed): wrappers,
#     expansions, escapes, `git -c`, --git-dir/--work-tree/--namespace,
#     and git aliases that may run push
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
      # Alternate destination or remote-side program: never auto-approve.
      --repo*|--receive-pack*|--exec*) return 0 ;;
      --push-option|-o) shift ;;
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

  # Must be a real repo, and the destination an already-configured remote —
  # never a URL or path (exfiltration, ext:: transports).
  _gp_git "$dir" rev-parse --git-dir >/dev/null || return 0
  _gp_git "$dir" remote | grep -qxF -- "$remote" || return 0
  [[ "$(_gp_git "$dir" config --bool "remote.$remote.mirror")" == true ]] && return 0

  # An earlier git command in the same line may have changed HEAD, tags,
  # aliases, remotes or config; what we read from the repo now is stale.
  [[ -n "${_GP_MUTATED:-}" ]] && return 0

  if (( ${#refspecs[@]} == 0 )); then
    # Configured push refspecs decide the target, not the current branch.
    [[ -n "$(_gp_git "$dir" config --get-all "remote.$remote.push")" ]] && return 0
    local target
    target="$(_gp_implicit_target "$dir")"
    [[ -z "$target" ]] && return 0
    _gp_is_protected "$dir" "$remote" "$target"
    return
  fi

  local r src dst
  for r in "${refspecs[@]}"; do
    [[ "$r" == +* || "$r" == *'*'* ]] && return 0   # force, or glob refspec
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
    # git DWIMs "heads/main" to refs/heads/main; anything else under refs/
    # (remotes, notes, namespaces) is unusual enough to ask about.
    case "$dst" in
      refs/heads/*) dst="${dst#refs/heads/}" ;;
      refs/*)       return 0 ;;
      heads/*)      dst="${dst#heads/}" ;;
    esac
    _gp_is_protected "$dir" "$remote" "$dst" && return 0
  done
  return 1
}

git_push_needs_review() {
  local cmd="$1" dir="${2:-$PWD}"
  local seg i gdir
  local -a w
  local unknown_dir="/nonexistent/git-push-unknown-dir"
  _GP_MUTATED=""

  # Fail closed: this parser is a word splitter, not a shell. Anything it
  # cannot model in a segment that mentions both git and push is deferred:
  # wrappers (env, command, sudo, xargs, sh -c, VAR=x prefixes, subshells,
  # the git-push binary), expansions/escapes ($ ` \ ( ) { }), git -c
  # overrides, alternate git dirs/namespaces, push-capable aliases.
  local mentions

  # Split into simple commands on ; & && || | and newlines, tracking `cd`.
  # fd redirects (2>&1, >&2, &>) are blanked first so '&' splits cleanly.
  while IFS= read -r seg; do
    mentions=""
    [[ "$seg" =~ (^|[^[:alnum:]_])git([^[:alnum:]_]|$) \
       && "$seg" =~ (^|[^[:alnum:]_])push([^[:alnum:]_]|$) ]] && mentions=1
    if [[ -n "$mentions" && "$seg" =~ [\$\`\\\(\)\{\}] ]]; then
      return 0
    fi

    read -ra w <<< "$seg"
    (( ${#w[@]} == 0 )) && continue
    for i in "${!w[@]}"; do w[i]="${w[i]//[\"\']/}"; done

    case "${w[0]}" in
      cd|pushd)
        if [[ "${w[1]:-}" == - || "${w[1]:-}" == [-+]* ]]; then
          dir="$unknown_dir"
        else
          dir="$(_gp_resolve_dir "$dir" "${w[1]:-$HOME}")"
        fi
        continue ;;
      popd) dir="$unknown_dir"; continue ;;
    esac
    if [[ "${w[0]}" != git ]]; then
      [[ -n "$mentions" ]] && return 0
      continue
    fi

    # Skip git's global options up to the subcommand.
    i=1 gdir="$dir"
    while (( i < ${#w[@]} )); do
      case "${w[i]}" in
        -C) gdir="$(_gp_resolve_dir "$dir" "${w[i+1]:-.}")"; i=$((i+2)) ;;
        -c|-c*|--config-env*|--git-dir*|--work-tree*|--namespace*|--exec-path*)
          [[ -n "$mentions" ]] && return 0
          _GP_MUTATED=1
          [[ "${w[i]}" == *=* || "${w[i]}" == -c?* ]] && i=$((i+1)) || i=$((i+2)) ;;
        -*) i=$((i+1)) ;;
        *) break ;;
      esac
    done
    case "${w[i]:-}" in
      push) ;;
      # Read-only, or changes only the working tree/index/current-branch
      # commits — none of these alter what a later push would target.
      status|log|diff|show|fetch|pull|add|commit|stash|rev-parse|ls-files|\
      ls-remote|describe|shortlog|blame|grep|cat-file|show-ref|for-each-ref|\
      merge-base|rev-list|reflog|version|help)
        continue ;;
      *)
        # A git alias may expand to push (or to anything, if it is '!shell').
        local alias_val
        alias_val="$(_gp_git "$gdir" config --get "alias.${w[i]:-}")"
        if [[ -n "$alias_val" ]] \
           && [[ "$alias_val" == '!'* || "$alias_val" =~ (^|[[:space:]])push([[:space:]]|$) ]]; then
          return 0
        fi
        # After a state change, an unknown subcommand may be an alias defined
        # earlier in this same line (git config alias.x push && git x).
        [[ -n "$_GP_MUTATED" && "$cmd" =~ (^|[^[:alnum:]_])push([^[:alnum:]_]|$) ]] && return 0
        # Anything else (checkout, switch, branch, tag, config, remote,
        # update-ref, symbolic-ref, reset, …) may change HEAD, refs, aliases
        # or remotes before the push runs.
        _GP_MUTATED=1
        continue ;;
    esac

    _gp_args_need_review "$gdir" "${w[@]:i+1}" && return 0
  done < <(printf '%s\n' "$cmd" \
    | perl -pe 's/\d*>&\d*-?/ /g; s/&>>?/ /g; s/\|\||&&|[;|&]/\n/g')

  return 1
}
