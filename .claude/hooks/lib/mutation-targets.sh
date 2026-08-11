# =============================================================================
# mutation-targets.sh — Shared "what does this command destroy?" extractor
#
# Walks a shell command pipeline segment by segment, tracks `cd` as it goes,
# and collects the paths each segment would overwrite, delete, or move.
# Consumed by:
#   • bash-2 — blocks when a target has uncommitted git changes
#   • bash-7 — blocks when a target is hook enforcement infrastructure
#
# Sets these globals (reset on every call):
#   MUT_OP_TYPE       human-readable description of the operation found
#   MUT_TARGETS       absolute paths whose *contents* would be destroyed
#   MUT_META_TARGETS  absolute paths whose metadata changes (chmod/chown)
#   MUT_WHOLE_TREE    non-empty when the command hits the whole working tree
#                     (git clean / git reset --hard / patch) and no single
#                     target can be named
#
# Deliberately conservative: globs, variables, and quoted paths containing
# spaces are skipped rather than guessed at. This extractor raises the cost of
# an accidental destructive command; it is not a sandbox and cannot be one.
# =============================================================================

# ---------------------------------------------------------------------------
# Collapse '.' and '..' segments in an absolute path (no filesystem access).
# ---------------------------------------------------------------------------
_mut_normalize() {
  local p="$1"
  local -a out=()
  local part joined="" oldIFS="$IFS"
  IFS='/'
  for part in $p; do
    case "$part" in
      ''|'.') continue ;;
      '..')   [[ ${#out[@]} -gt 0 ]] && unset "out[$(( ${#out[@]} - 1 ))]" ;;
      *)      out+=("$part") ;;
    esac
  done
  IFS="$oldIFS"
  for part in ${out[@]+"${out[@]}"}; do joined="$joined/$part"; done
  printf '%s' "${joined:-/}"
}

# ---------------------------------------------------------------------------
# Add a candidate target, resolved against the segment's effective cwd.
# Usage: _mut_add <array-name> <token> <cwd>
# ---------------------------------------------------------------------------
_mut_add() {
  local arr="$1" t="$2" cwd="$3"

  t="${t//\"/}"
  t="${t//\'/}"

  [[ -z "$t" ]] && return 0
  [[ "$t" == -* ]] && return 0                       # flag, not a path
  [[ "$t" == "/dev/null" || "$t" == "-" ]] && return 0
  [[ "$t" == *'*'* || "$t" == *'?'* ]] && return 0    # unresolvable glob
  [[ "$t" == *'['* ]] && return 0
  [[ "$t" == '$'* || "$t" == *'`'* ]] && return 0     # needs expansion

  local abs
  if [[ "$t" == /* ]]; then abs="$t"; else abs="$cwd/$t"; fi
  abs="$(_mut_normalize "$abs")"

  if [[ "$arr" == "meta" ]]; then
    MUT_META_TARGETS+=("$abs")
  else
    MUT_TARGETS+=("$abs")
  fi
}

# ---------------------------------------------------------------------------
# extract_mutation_targets <command>
# ---------------------------------------------------------------------------
extract_mutation_targets() {
  local cmd="$1"

  MUT_OP_TYPE=""
  MUT_TARGETS=()
  MUT_META_TARGETS=()
  MUT_WHOLE_TREE=""

  local cwd="${CWD:-${PROJECT_DIR:-$PWD}}"

  # Split the pipeline into segments on ; && || | so that a command hidden
  # behind a prefix (`cd .claude && rm settings.json`) is still analysed.
  local segments
  segments="$(printf '%s' "$cmd" | perl -pe 's/(\|\||&&|;|\|)/\n/g')"

  local seg
  while IFS= read -r seg; do
    # Trim
    seg="$(printf '%s' "$seg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$seg" ]] && continue

    local -a toks=()
    read -r -a toks <<< "$seg"
    local head="${toks[0]:-}"

    # ── cd: retarget the effective cwd for every later segment ──────────────
    if [[ "$head" == "cd" && -n "${toks[1]:-}" ]]; then
      local d="${toks[1]}"
      d="${d//\"/}"; d="${d//\'/}"
      if [[ "$d" == /* ]]; then cwd="$(_mut_normalize "$d")"
      elif [[ "$d" != '$'* && "$d" != '~'* ]]; then cwd="$(_mut_normalize "$cwd/$d")"
      fi
      continue
    fi

    # ── Truncating redirect: `> file` but not `>>` and not `>&` ─────────────
    if printf '%s' "$seg" | grep -qE '(^|[^>&0-9])>([^>&=]|$)'; then
      MUT_OP_TYPE="${MUT_OP_TYPE:-overwrite via redirect}"
      local t
      while IFS= read -r t; do
        _mut_add content "$t" "$cwd"
      done < <(printf '%s' "$seg" | \
        perl -ne 'while (m{(?<![>&0-9])>(?![>&=])\s*([^\s|&;<>]+)}g) { print "$1\n" }')
    fi

    case "$head" in
      # ── Deletion ───────────────────────────────────────────────────────────
      rm|unlink|shred)
        MUT_OP_TYPE="deletion"
        local i
        for (( i=1; i<${#toks[@]}; i++ )); do
          _mut_add content "${toks[$i]}" "$cwd"
        done
        ;;

      # ── Move: source disappears, destination is overwritten ───────────────
      mv)
        MUT_OP_TYPE="${MUT_OP_TYPE:-move}"
        local i
        for (( i=1; i<${#toks[@]}; i++ )); do
          _mut_add content "${toks[$i]}" "$cwd"
        done
        ;;

      # ── Destination-overwriting copies/links ──────────────────────────────
      cp|install|ln|rsync|scp)
        # Only the final operand is written to. `ln` without -f cannot clobber
        # an existing path, so it is not destructive.
        if [[ "$head" != "ln" ]] || printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f'; then
          MUT_OP_TYPE="${MUT_OP_TYPE:-overwrite via $head}"
          _mut_add content "${toks[$(( ${#toks[@]} - 1 ))]}" "$cwd"
        fi
        ;;

      # ── In-place editors ──────────────────────────────────────────────────
      truncate|ed|ex)
        MUT_OP_TYPE="${MUT_OP_TYPE:-in-place edit ($head)}"
        _mut_add content "${toks[$(( ${#toks[@]} - 1 ))]}" "$cwd"
        ;;

      # ── patch: rewrites whatever the diff names; unresolvable here ────────
      patch)
        MUT_OP_TYPE="${MUT_OP_TYPE:-patch application}"
        MUT_WHOLE_TREE="patch rewrites every file named in the diff"
        ;;

      # ── Permission / ownership changes (metadata only) ────────────────────
      chmod|chown|chflags)
        MUT_OP_TYPE="${MUT_OP_TYPE:-permission change}"
        # The mode operand may itself look like a flag (`chmod -x file`), so
        # only known option letters are skipped; the first survivor is the
        # mode/owner and everything after it is a path.
        local i tk mode_seen=""
        for (( i=1; i<${#toks[@]}; i++ )); do
          tk="${toks[$i]}"
          case "$tk" in
            -R|-r|-h|-v|-f|-P|-L|-H|--*) continue ;;
          esac
          if [[ -z "$mode_seen" ]]; then mode_seen=1; continue; fi
          _mut_add meta "$tk" "$cwd"
        done
        ;;

      # ── git subcommands that discard working-tree state ───────────────────
      git)
        local sub="${toks[1]:-}"
        # skip global flags like `git -C dir checkout`
        local gi=1
        while [[ "${toks[$gi]:-}" == -* ]]; do gi=$(( gi + 2 )); done
        sub="${toks[$gi]:-}"

        case "$sub" in
          clean)
            if printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f'; then
              MUT_OP_TYPE="${MUT_OP_TYPE:-git clean}"
              MUT_WHOLE_TREE="git clean -f permanently removes untracked files"
            fi
            ;;
          reset)
            if printf '%s' "$seg" | grep -qE '(--hard|--merge|--keep)\b'; then
              MUT_OP_TYPE="${MUT_OP_TYPE:-git reset --hard}"
              MUT_WHOLE_TREE="git reset --hard discards all uncommitted changes"
            fi
            ;;
          checkout|restore)
            # Restore the previous op if this turns out to be a branch switch,
            # so an earlier segment's finding is not clobbered.
            local prev_op="$MUT_OP_TYPE"
            MUT_OP_TYPE="${MUT_OP_TYPE:-git $sub (discards working-tree changes)}"
            local j seen_sep="" any=""
            for (( j=gi+1; j<${#toks[@]}; j++ )); do
              local tk="${toks[$j]}"
              if [[ "$tk" == "--" ]]; then seen_sep=1; continue; fi
              [[ "$tk" == -* ]] && continue
              # For checkout, only paths after `--` (or `.`) are file operands
              if [[ "$sub" == "checkout" && -z "$seen_sep" && "$tk" != "." ]]; then
                continue
              fi
              if [[ "$tk" == "." ]]; then
                MUT_WHOLE_TREE="git $sub . discards changes across the tree"
                any=1; continue
              fi
              _mut_add content "$tk" "$cwd"; any=1
            done
            [[ -z "$any" ]] && MUT_OP_TYPE="$prev_op"
            ;;
        esac
        ;;
    esac

    # ── sed -i / perl -i anywhere in the segment ────────────────────────────
    if printf '%s' "$seg" | grep -qE '\b(sed|perl|gsed)\s+(-i|--in-place)'; then
      MUT_OP_TYPE="${MUT_OP_TYPE:-in-place edit}"
      _mut_add content "${toks[$(( ${#toks[@]} - 1 ))]}" "$cwd"
    fi

    # ── dd of=file ─────────────────────────────────────────────────────────
    if printf '%s' "$seg" | grep -qE '\bdd\b.*\bof='; then
      MUT_OP_TYPE="${MUT_OP_TYPE:-dd overwrite}"
      local dd_t
      dd_t="$(printf '%s' "$seg" | grep -oE 'of=[^[:space:]]+' | sed 's/^of=//')"
      _mut_add content "$dd_t" "$cwd"
    fi

    # ── tee (overwrites unless -a) ─────────────────────────────────────────
    if printf '%s' "$seg" | grep -qE '\btee\b' && ! printf '%s' "$seg" | grep -qE '\btee\s+(-[a-zA-Z]*a)'; then
      MUT_OP_TYPE="${MUT_OP_TYPE:-tee overwrite}"
      local tee_t
      tee_t="$(printf '%s' "$seg" | grep -oE '\btee\b([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[^[:space:]|&;]+' | awk '{print $NF}')"
      _mut_add content "$tee_t" "$cwd"
    fi

  done <<< "$segments"

  return 0
}
