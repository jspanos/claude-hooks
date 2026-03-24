# =============================================================================
# bash-4-inline-scripts.sh — Rule: No inline scripts; use scripts/ directory
#
# Detected patterns:
#   • heredoc writing to a file: cat > file.sh << EOF
#   • shebang line written via echo/printf to a .sh/.py file
#   • bash -c / sh -c with 4+ chained commands (should be a script)
#   • python -c / node -e with >150 chars of inline code
#
# On detection: deny with instructions to use scripts/ + scripts/SCRIPTS.md
# =============================================================================

bash_check_inline_scripts() {
  local cmd="$1"
  local reason=""

  # ── Pattern 1: heredoc writing to a script file ───────────────────────────
  # Matches: cat > file.sh << 'EOF'   or   tee script.py << EOF
  if printf '%s' "$cmd" | grep -qE '(cat|tee)\s*(>+\s*)?\S*\.(sh|bash|py|js|ts|rb|pl|zsh|fish)\s*<<' || \
     printf '%s' "$cmd" | grep -qE '(cat|tee)\s*>+\s*\S+\s*<<.*EOF'; then
    reason="heredoc creating a script file inline"
  fi

  # ── Pattern 2: echo/printf writing a shebang to a script file ─────────────
  if [[ -z "$reason" ]] && \
     printf '%s' "$cmd" | grep -qE '(echo|printf)\s+.#!/' && \
     printf '%s' "$cmd" | grep -qE '>+\s*\S+\.(sh|bash|py|js|ts|rb|pl|zsh|fish)'; then
    reason="writing shebang line to create script inline"
  fi

  # ── Pattern 3: bash/sh/zsh -c with 4+ command separators ─────────────────
  if [[ -z "$reason" ]] && \
     printf '%s' "$cmd" | grep -qE '^\s*(bash|sh|zsh)\s+-c\s+'; then
    # Extract inner content (strip outer quotes, best-effort)
    local inner
    inner="$(printf '%s' "$cmd" | sed -E "s/^[[:space:]]*(bash|sh|zsh)[[:space:]]+-c[[:space:]]*['\"]//;s/['\"][[:space:]]*$//")"
    # Count all command delimiters: semicolons, logical ops, and newlines
    # wc -l counts newlines (0 for single-line), each newline = a command boundary
    local sep_count newline_count total
    sep_count="$(printf '%s' "$inner" | grep -oE '(;|&&|\|\|)' | wc -l | tr -d ' ')"
    newline_count="$(printf '%s' "$inner" | wc -l | tr -d ' ')"
    total=$(( sep_count + newline_count ))
    if [[ "$total" -ge 4 ]]; then
      reason="bash -c with $((total+1)) commands — this is a script"
    fi
  fi

  # ── Pattern 4: python/node/ruby -c/-e with substantial inline code ─────────
  if [[ -z "$reason" ]] && \
     printf '%s' "$cmd" | grep -qE '^\s*(python[23]?|node|ruby)\s+-[ce]\s+'; then
    local inner
    inner="$(printf '%s' "$cmd" | sed -E "s/^[[:space:]]*(python[23]?|node|ruby)[[:space:]]+-[ce][[:space:]]*['\"]//;s/['\"][[:space:]]*$//")"
    local char_count="${#inner}"
    if [[ "$char_count" -gt 150 ]]; then
      local lang
      lang="$(printf '%s' "$cmd" | grep -oE 'python[23]?|node|ruby' | head -1)"
      reason="inline $lang script with $char_count chars — this is a script"
    fi
  fi

  [[ -z "$reason" ]] && return 0

  # Build advice based on whether scripts/SCRIPTS.md exists
  local scripts_advice
  if [[ -f "$PROJECT_DIR/scripts/SCRIPTS.md" ]]; then
    scripts_advice="Check 'scripts/SCRIPTS.md' first — a similar script may already exist and just needs an update."
  else
    scripts_advice="The scripts/ registry does not exist yet. Create 'scripts/SCRIPTS.md' when you write your first script (template below)."
  fi

  deny_and_log "bash-4" \
"Inline script detected: $reason.

Use the scripts/ directory workflow instead:
  1. $scripts_advice
  2. If reusing: modify the existing script, expand --help, and update SCRIPTS.md.
  3. If creating new:
       a. Create scripts/<descriptive-name>.sh (or .py) using the Write tool
       b. Start with: #!/usr/bin/env bash / set -euo pipefail
       c. Add --help / -h that prints usage, options, and examples
       d. chmod +x scripts/<name>.sh
       e. Add a row to scripts/SCRIPTS.md: | scripts/<name>.sh | description | options |
  4. Run with: ./scripts/<name>.sh [options] [args]

SCRIPTS.md template row:
  | scripts/<name>.sh | What it does | --flag desc |"
}
