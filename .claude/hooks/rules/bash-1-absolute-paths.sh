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

    # Path is inside the project directory → suggest relative path
    if [[ -n "$PROJECT_DIR" && "$path" == "$PROJECT_DIR"/* ]]; then
      local rel="${path#$PROJECT_DIR/}"
      deny_and_log "bash-1" \
        "Absolute project path: '$path'. Use './$rel' instead. Absolute paths trigger unnecessary Claude Code permission prompts."
    fi

    # Path is inside HOME but outside project
    if [[ -n "$HOME" && "$path" == "$HOME"/* && "$path" != "$PROJECT_DIR"/* ]]; then
      deny_and_log "bash-1" \
        "Absolute home-directory path: '$path'. Use paths relative to the project directory instead."
    fi

  done <<< "$raw_paths"
}
