# =============================================================================
# bash-9-blocking-waits.sh — Rule: foreground blocking waits + timeout defaults
#
# Two halves, both aimed at wall-clock waste rather than safety:
#
#   bash_check_blocking_waits  — DENY commands that block the foreground while
#     waiting on external state (CI runs, PR checks, rollouts, dev servers,
#     long sleeps, until/sleep poll loops). These must run with
#     run_in_background:true, or as a Monitor, so the agent keeps working.
#
#   bash_suggest_timeout — ECHO a timeout (ms) for commands that legitimately
#     take minutes of real work (test suites, builds, installs) but carry no
#     explicit timeout, so they don't get silently killed at the 120s default.
#     Also clamps anything above the 600s ceiling.
#
# Motivation (measured over ~19k Bash calls in .claude/logs/audit.jsonl):
#   • 29% of all Bash wall time was spent in `sleep` and `until`-poll loops
#   • ~170 calls hit the 600s ceiling and were killed — almost all of them
#     `gh run watch` / `gh pr checks --watch` / hand-rolled CI poll loops
#   • only 1.3% of calls used run_in_background
# =============================================================================

# ---------------------------------------------------------------------------
# Timeout ceiling and family defaults (milliseconds)
# ---------------------------------------------------------------------------
BASH9_MAX_TIMEOUT_MS=600000
BASH9_TEST_TIMEOUT_MS=300000
BASH9_BROWSER_TEST_TIMEOUT_MS=480000
BASH9_BUILD_TIMEOUT_MS=600000

# ---------------------------------------------------------------------------
# Deny foreground waits on external state.
# Usage: bash_check_blocking_waits "$COMMAND" "$RUN_IN_BACKGROUND"
# ---------------------------------------------------------------------------
bash_check_blocking_waits() {
  local cmd="$1"
  local bg="${2:-false}"

  # Backgrounded calls are exactly what this rule is asking for.
  [[ "$bg" == "true" ]] && return 0

  local howto="Re-issue with run_in_background:true (one notification when it finishes), or use the Monitor tool if you want an event per state change. Both let you keep working while it waits."

  # ── Hand-rolled poll loops: until/while/for ... do ... sleep ──────────────
  if printf '%s' "$cmd" | grep -qE '\b(until|while|for)\b.*\bdo\b.*\bsleep\b'; then
    deny_and_log "bash-9" \
      "Foreground poll loop (until/while + sleep) blocks until the remote state changes — in this repo's audit log that pattern averaged minutes per call and frequently hit the 600s ceiling and was killed. $howto"
  fi

  # ── Long bare sleeps ─────────────────────────────────────────────────────
  local longest
  longest="$(printf '%s' "$cmd" \
    | grep -oE '(^|[;&|(])[[:space:]]*sleep[[:space:]]+[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?$' \
    | sort -g | tail -1)"
  if [[ -n "$longest" ]] && awk "BEGIN{exit !($longest > 5)}"; then
    deny_and_log "bash-9" \
      "'sleep ${longest}' blocks the foreground for ${longest}s doing nothing. Sleeps over 5s belong in a backgrounded command. $howto"
  fi

  # ── gh: CI run / PR check watching ───────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\bgh\b[^;&|]*\b(run[[:space:]]+watch|--watch)\b'; then
    deny_and_log "bash-9" \
      "'gh run watch' / 'gh pr checks --watch' blocks for the entire CI run. CI regularly outruns the 600s Bash ceiling, so the call gets killed and the wait is wasted. $howto"
  fi

  # ── Cluster / cloud waiters ──────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\bkubectl\b[^;&|]*\b(wait|rollout[[:space:]]+status)\b'; then
    deny_and_log "bash-9" \
      "'kubectl wait' / 'kubectl rollout status' blocks until the cluster converges. $howto"
  fi

  if printf '%s' "$cmd" | grep -qE '\b(docker|aws|gcloud|az)\b[^;&|]*\bwait\b'; then
    deny_and_log "bash-9" \
      "Cloud/container 'wait' subcommand blocks the foreground on remote state. $howto"
  fi

  if printf '%s' "$cmd" | grep -qE '\b(flux|argocd)\b[^;&|]*\b(reconcile|wait)\b'; then
    deny_and_log "bash-9" \
      "GitOps reconcile/wait blocks until the controller converges. $howto"
  fi

  # ── Streams and servers that never return ────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\btail\b[^;&|]*[[:space:]]-[a-zA-Z]*f\b'; then
    deny_and_log "bash-9" \
      "'tail -f' never exits, so in the foreground it always burns the full timeout. Use the Monitor tool to stream matching lines as events, or background it. $howto"
  fi

  if printf '%s' "$cmd" | grep -qE '\b(npm|pnpm|yarn|bun)[[:space:]]+run[[:space:]]+(dev|start|serve|watch)\b|\bnext[[:space:]]+dev\b|\bvite\b([[:space:]]|$)|\bnodemon\b|\buvicorn\b|\bflask[[:space:]]+run\b|\brails[[:space:]]+s(erver)?\b'; then
    deny_and_log "bash-9" \
      "Dev servers run until killed, so a foreground call just waits out the timeout. $howto"
  fi

  # ── Explicit long-poll flags on watchers ─────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '\b(watch|entr)\b[[:space:]]+-'; then
    deny_and_log "bash-9" \
      "'watch'/'entr' re-run a command forever in the foreground. $howto"
  fi
}

# ---------------------------------------------------------------------------
# Suggest a timeout (ms) for slow-but-legitimate work.
# Echoes the timeout to use, or nothing if no change is needed.
# Usage: NEW="$(bash_suggest_timeout "$COMMAND" "$TIMEOUT_MS")"
# ---------------------------------------------------------------------------
bash_suggest_timeout() {
  local cmd="$1"
  local current="${2:-}"

  # Clamp anything above the ceiling — the tool rejects larger values outright.
  if [[ -n "$current" && "$current" =~ ^[0-9]+$ ]]; then
    if (( current > BASH9_MAX_TIMEOUT_MS )); then
      echo "$BASH9_MAX_TIMEOUT_MS"
    fi
    return 0
  fi

  # Browser/e2e suites: slowest test family by a wide margin.
  if printf '%s' "$cmd" | grep -qE '\b(playwright|cypress|puppeteer|selenium)\b'; then
    echo "$BASH9_BROWSER_TEST_TIMEOUT_MS"
    return 0
  fi

  # Test suites and full lint+test chains.
  if printf '%s' "$cmd" | grep -qE '\b(pytest|jest|vitest|mocha|rspec|phpunit|tox|nox)\b|\b(go|cargo|npm|pnpm|yarn|bun)[[:space:]]+test\b|\bdotnet[[:space:]]+test\b|\bgradlew?[[:space:]]+test\b|\bmvn\b[^;&|]*\btest\b|(^|[[:space:]./])run-tests\.sh\b'; then
    echo "$BASH9_TEST_TIMEOUT_MS"
    return 0
  fi

  # Builds, installs, image work: minutes of real progress, no output until done.
  if printf '%s' "$cmd" | grep -qE '\b(npm|pnpm|yarn|bun)[[:space:]]+(ci|install)\b|\buv[[:space:]]+(sync|add|lock)\b|\bpoetry[[:space:]]+(install|lock)\b|\bbundle[[:space:]]+install\b|\bcargo[[:space:]]+(build|check|clippy)\b|\bgo[[:space:]]+build\b|\bdocker[[:space:]]+(build|compose[[:space:]]+build)\b|\bbrew[[:space:]]+(install|upgrade)\b|\bmake\b|\bxcodebuild\b|\bgradlew?[[:space:]]+(build|assemble)\b|\bmvn[[:space:]]+(package|install)\b|\b(next|vite|webpack|tsc)[[:space:]]+build\b|\btsc[[:space:]]+-b\b'; then
    echo "$BASH9_BUILD_TIMEOUT_MS"
    return 0
  fi
}
