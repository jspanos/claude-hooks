# =============================================================================
# bash-8-interpreter-file-ops.sh — Rule: No filesystem mutation via -c/-e
#
# The known bypass: every shell-level guard here matches on command text, so
# `rm secrets.txt` is blocked while
#     uv run python3 -c "import os; os.remove('secrets.txt')"
# does the same thing through an interpreter no shell rule models. bash-4 only
# caught these past 150 characters and bash-6 only gated bare `python3`, so a
# short one-liner — or any node/perl/ruby equivalent — passed cleanly.
#
# This rule blocks inline interpreter code that deletes, overwrites, renames,
# or chmods files, or that shells out (os.system/subprocess/child_process) to
# re-enter the shell with the bash rules already behind it. Length is
# irrelevant; the API being called is what matters.
#
# LIMITATION — read this before trusting it:
#   An interpreter is Turing-complete. Obfuscation defeats any pattern match
#   (getattr(os, 'rem'+'ove'), base64, importlib). This rule raises the cost of
#   the careless and the obvious path; it is NOT a security boundary. Real
#   containment requires OS-level sandboxing, which a hook cannot provide.
# =============================================================================

bash_check_interpreter_file_ops() {
  local cmd="$1"

  # Flatten newlines so multi-line/continued commands still match
  local flat
  flat="$(printf '%s' "$cmd" | tr '\n' ' ')"

  # Interpreter invocation, at start of command or after a pipeline boundary.
  # Prefixes cover the forms bash-6 allowlists, so its venv exemption does not
  # reopen the hole.
  local INTERP='(uv[[:space:]]+run[[:space:]]+python[23]?|(\.venv|venv)/bin/python[23]?|python[23]?|node|deno|bun|ruby|perl|php)'

  # ── Heredoc into an interpreter is a script by any other name ─────────────
  if printf '%s' "$flat" | grep -qE "(^|[|&;][|&]?[[:space:]]*)${INTERP}[[:space:]]+(-[[:space:]]+)?<<"; then
    deny_and_log "bash-8" \
      "Heredoc piped into an interpreter is an inline script.

Write it to scripts/<name>.py (or .js) with the Write tool, add a row to
scripts/SCRIPTS.md, then run it as a separate step."
  fi

  printf '%s' "$flat" | grep -qE "(^|[|&;][|&]?[[:space:]]*)${INTERP}[[:space:]]+-[cerR][[:space:]]" || return 0

  # Strip through the last -c/-e/-r flag and its opening quote
  local inner
  inner="$(printf '%s' "$flat" | \
    sed -E "s@^.*${INTERP}[[:space:]]+-[cerR][[:space:]]*['\"]@@;s/['\"][[:space:]]*\$//")"

  # ── Filesystem-mutating APIs ──────────────────────────────────────────────
  # Node's fs methods are usually reached as require('fs').unlinkSync(...) or
  # fsp.writeFile(...), so the *Sync family is matched bare; the ambiguous
  # non-Sync names still require an fs. prefix to avoid false positives.
  local FS_MUTATE='os\.(remove|unlink|rmdir|removedirs|rename|replace|truncate|chmod|chown|mkdir|makedirs)|shutil\.(rmtree|move|copy|copyfile|copytree|chown)|\.(write_text|write_bytes|unlink|rmdir|rename|replace|touch|chmod)[[:space:]]*\(|open[[:space:]]*\([^)]*,[[:space:]]*[a-z]*=?['"'"'"][rbt+]*[wax][rbt+]*['"'"'"]|\.(unlinkSync|rmSync|rmdirSync|writeFileSync|appendFileSync|truncateSync|renameSync|copyFileSync|chmodSync|mkdirSync)[[:space:]]*\(|fs\.(unlink|rm|rmdir|writeFile|appendFile|truncate|rename|copyFile|chmod)[[:space:]]*\(|File\.(delete|unlink|write|rename)|FileUtils\.(rm|rm_rf|rm_r|mv|cp)|IO\.write'

  # ── Shelling out from inside the interpreter (rule-layer escape) ──────────
  local SHELL_OUT='os\.system|os\.popen|os\.exec|subprocess\.|child_process|execSync|spawnSync|Kernel\.system|IO\.popen|backticks'

  local reason=""
  if printf '%s' "$inner" | grep -qE "$FS_MUTATE"; then
    reason="inline interpreter code that modifies or deletes files"
  elif printf '%s' "$inner" | grep -qE "$SHELL_OUT"; then
    reason="inline interpreter code that shells out (os.system/subprocess/child_process)"
  fi

  [[ -z "$reason" ]] && return 0

  local lang
  lang="$(printf '%s' "$flat" | grep -oE 'python[23]?|node|deno|bun|ruby|perl|php' | tail -1)"

  deny_and_log "bash-8" \
    "Blocked: $reason.

Running file mutations through '$lang -c/-e' bypasses the shell-level guards
(bash-2 uncommitted-file protection, bash-5 bulk-deletion checks, bash-7 hook
protection) because those rules read shell commands, not interpreter code.

Use instead:
  • Deleting/moving files    → run rm/mv directly so bash-2 can check git state
  • Editing file contents    → the Edit or Write tool (keeps changes in git)
  • Real multi-step logic    → scripts/<name>.py, registered in scripts/SCRIPTS.md
  • Shelling out             → run the command directly in Bash

Note: this rule matches obvious API calls only. It is a guardrail against
accidents, not a sandbox — do not rely on it to contain untrusted code."
}
