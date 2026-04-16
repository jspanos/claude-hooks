# =============================================================================
# bash-1-absolute-paths.sh — Rule: No absolute project/home paths
#
# Absolute paths within $PROJECT_DIR or $HOME trigger Claude Code permission
# prompts for operations that should just work with relative paths.
# System paths (/usr, /bin, /opt/homebrew, /tmp, /dev, etc.) are allowed.
# =============================================================================

bash_check_absolute_paths() {
  local cmd="$1"

  # Extract tokens that look like /absolute/paths from the command.
  # We use perl for reliable extraction across all macOS bash versions.
  local raw_paths
  raw_paths="$(printf '%s' "$cmd" | \
    perl -ne 'while (m{(?:^|[\s"'"'"'`=])(\/[^\s"'"'"'`|;&<>\\]+)}g) { print "$1\n" }' | \
    sort -u)"

  # Prefixes that are always safe to use as absolute paths
  local -a SYSTEM_PREFIXES
  SYSTEM_PREFIXES=(
    /usr/ /bin/ /sbin/ /lib/ /lib64/ /libexec/
    /opt/homebrew/ /opt/local/ /opt/pkg/
    /System/ /Library/ /Applications/ /Volumes/
    /tmp /dev/ /proc/ /sys/ /run/
    /var/ /etc/ /home/linuxbrew/
    /nix/ /snap/
  )

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    # Strip trailing punctuation / quote that bled in
    path="${path%%[,;)\"\'\\]}"
    [[ -z "$path" || "$path" == "/" ]] && continue

    # Allow /dev/null explicitly
    [[ "$path" == "/dev/null" ]] && continue

    # Check against system prefixes
    local is_system=false
    for pfx in "${SYSTEM_PREFIXES[@]}"; do
      if [[ "$path" == "$pfx"* || "$path" == "${pfx%/}" ]]; then
        is_system=true; break
      fi
    done
    $is_system && continue

    # Compute effective CWD once
    local effective_cwd="${CWD:-$PROJECT_DIR}"

    # Path is the project directory itself or inside it → suggest relative path from CWD
    if [[ -n "$PROJECT_DIR" && ( "$path" == "$PROJECT_DIR" || "$path" == "$PROJECT_DIR"/* ) ]]; then
      local rel
      rel="$(perl -e 'use File::Spec; print File::Spec->abs2rel($ARGV[0], $ARGV[1])' "$path" "$effective_cwd")"

      # Exact project dir match is inherently safe — skip filesystem resolve
      if [[ "$path" == "$PROJECT_DIR" ]]; then
        local corrected_cmd
        corrected_cmd="$(printf '%s' "$cmd" | sed "s|$path|$rel|g")"
        deny_and_log "bash-1" \
          "Absolute project path: '$path'. Use '$rel' instead (from current directory). Suggested command: $corrected_cmd"
      else
        # Security: resolve the relative path and verify it stays within PROJECT_DIR
        local resolved
        resolved="$(cd "$effective_cwd" 2>/dev/null && perl -e 'use Cwd qw(abs_path); print abs_path($ARGV[0]) // ""' "$rel")"
        if [[ -z "$resolved" || "$resolved" != "$PROJECT_DIR"/* && "$resolved" != "$PROJECT_DIR" ]]; then
          deny_and_log "bash-1" \
            "Absolute project path: '$path'. Use a relative path instead. Absolute paths trigger unnecessary Claude Code permission prompts."
        else
          local corrected_cmd
          corrected_cmd="$(printf '%s' "$cmd" | sed "s|$path|$rel|g")"
          deny_and_log "bash-1" \
            "Absolute project path: '$path'. Use '$rel' instead (from current directory). Suggested command: $corrected_cmd"
        fi
      fi
      continue
    fi

    # Path is inside HOME but outside project → still suggest a relative equivalent
    if [[ -n "$HOME" && "$path" == "$HOME"/* ]]; then
      local rel
      rel="$(perl -e 'use File::Spec; print File::Spec->abs2rel($ARGV[0], $ARGV[1])' "$path" "$effective_cwd")"
      local corrected_cmd
      corrected_cmd="$(printf '%s' "$cmd" | sed "s|$path|$rel|g")"
      deny_and_log "bash-1" \
        "Absolute home-directory path: '$path'. Use '$rel' instead (from current directory). Suggested command: $corrected_cmd"
    fi

  done <<< "$raw_paths"
}
