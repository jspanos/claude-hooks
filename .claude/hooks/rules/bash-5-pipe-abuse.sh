# =============================================================================
# bash-5-pipe-abuse.sh — Rule: Pipe and redirect abuse detection
#
# Analyzes the full command pipeline for dangerous data-flow patterns:
#   • Remote code execution: curl/wget piped to interpreter
#   • Obfuscated execution: base64 -d | bash, eval $(cmd), $(curl ...)
#   • Bulk destruction: xargs rm, find -exec rm, find -delete
#   • Privilege escalation: anything | sudo/su
#   • System path writes: > /etc/..., tee /usr/...
#   • Bulk permission changes: xargs chmod
# =============================================================================

bash_check_pipe_abuse() {
  local cmd="$1"

  # ── Remote code execution via pipe ────────────────────────────────────────
  # curl/wget output piped directly to an interpreter
  if printf '%s' "$cmd" | grep -qE '(curl|wget)\b.*\|[^|]*\b(bash|sh|python[23]?|node|ruby|perl)\b'; then
    deny_and_log "bash-5" \
      "Network download piped directly to interpreter (curl|wget → bash/python/node). This is a supply-chain attack vector. Download to a file first, inspect it, then run it explicitly."
  fi

  # base64 -d | interpreter (obfuscated execution)
  if printf '%s' "$cmd" | grep -qE 'base64\b.*-d\b.*\|[^|]*\b(bash|sh|python[23]?|node|eval)\b'; then
    deny_and_log "bash-5" \
      "base64-decoded content piped to interpreter — obfuscated code execution pattern. Decode to a file first and inspect before running."
  fi

  # Pipe into eval
  if printf '%s' "$cmd" | grep -qE '\|[[:space:]]*eval\b'; then
    deny_and_log "bash-5" \
      "Piping into 'eval' is a code injection risk. Assign the value to a variable and validate it before using eval (or avoid eval entirely)."
  fi

  # Command substitution containing a network fetch: $(curl ...) or `wget ...`
  if printf '%s' "$cmd" | grep -qE '\$\((curl|wget)\b|` *(curl|wget)\b'; then
    deny_and_log "bash-5" \
      "Network fetch inside command substitution \$(curl ...) executes remote content as code. Fetch to a file, inspect, then run explicitly."
  fi

  # openssl decrypt piped to interpreter (another obfuscation technique)
  if printf '%s' "$cmd" | grep -qE 'openssl\b.*enc.*-d.*\|[^|]*\b(bash|sh|python|node)\b'; then
    deny_and_log "bash-5" \
      "Encrypted content decrypted and piped to interpreter — obfuscated execution pattern."
  fi

  # ── Bulk destructive operations ───────────────────────────────────────────
  # xargs rm — bulk deletion driven by piped filenames
  if printf '%s' "$cmd" | grep -qE '\|[^|]*xargs[^|]*\brm\b'; then
    deny_and_log "bash-5" \
      "Pipe to 'xargs rm' can bulk-delete many files. Verify the file list first by running without 'xargs rm', then perform deletions explicitly or use 'xargs echo rm' for a dry run."
  fi

  # find -exec rm {} or find -delete — recursive deletion
  if printf '%s' "$cmd" | grep -qE '\bfind\b.+(-exec[[:space:]]+rm\b|-delete\b)'; then
    deny_and_log "bash-5" \
      "find with -exec rm or -delete performs recursive deletion. Run the find command alone first to verify the match set, then add -delete or -exec rm after review."
  fi

  # xargs unlink — same risk as xargs rm
  if printf '%s' "$cmd" | grep -qE '\|[^|]*xargs[^|]*\bunlink\b'; then
    deny_and_log "bash-5" \
      "Pipe to 'xargs unlink' detected — bulk file deletion via pipe. Verify the file list before proceeding."
  fi

  # ── Privilege escalation via pipe ─────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\|[[:space:]]*(sudo|su)\b'; then
    deny_and_log "bash-5" \
      "Piping into sudo/su detected. Run sudo commands directly with explicit, reviewed arguments rather than passing arbitrary piped content to a privileged process."
  fi

  # ── Writes to system paths via redirect or tee ────────────────────────────
  if printf '%s' "$cmd" | grep -qE '>+[[:space:]]*/([^[:space:]]*(etc|usr|bin|sbin|lib|boot|sys)/[^[:space:]]*)'; then
    deny_and_log "bash-5" \
      "Output redirect to system directory detected. Writing to /etc, /usr, /bin, /sbin etc. is not allowed."
  fi

  if printf '%s' "$cmd" | grep -qE '\btee\b[^|]*(/(etc|usr|bin|sbin|lib|boot|sys)/)'; then
    deny_and_log "bash-5" \
      "tee writing to system directory detected. Writing to system paths is not allowed."
  fi

  # ── Bulk permission changes ───────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\|[^|]*xargs[^|]*\bchmod\b'; then
    deny_and_log "bash-5" \
      "Pipe to 'xargs chmod' performs bulk permission changes. Apply chmod to specific, reviewed files explicitly."
  fi

  # ── Write-then-execute pattern (permission laundering) ────────────────────
  # Creating a file and immediately running it in the same command chain
  if printf '%s' "$cmd" | grep -qE '(tee|cat[[:space:]]*>)[^;&&|]*\.(sh|py|rb|js)\b.*(&&|\|)[^;&&|]*(\./|bash[[:space:]]|sh[[:space:]])'; then
    deny_and_log "bash-5" \
      "Write-then-execute pattern detected: creating a script file and immediately running it in one command chain bypasses script review. Use the Write tool to create the file, then run it in a separate step."
  fi
}
