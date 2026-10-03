#!/usr/bin/env bash
# =============================================================================
# permission-request.test.sh — End-to-end tests for permission-request.sh
# Write/Edit path decisions (project, git work trees, elsewhere).
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$(cd "$TESTS_DIR/../.claude/hooks" && pwd)/permission-request.sh"

source "$TESTS_DIR/lib/assert.sh"

# ── Fixture: project repo, sibling repo, plain dir ───────────────────────────
TMP="$(cd "$(mktemp -d /tmp/claude-hooks-perm.XXXXXX)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/project" "$TMP/sibling/sub" "$TMP/plain" "$TMP/home/.claude/hooks"
git -C "$TMP/project" init -q
git -C "$TMP/sibling" init -q
git -C "$TMP/home" init -q          # dotfiles-style repo rooted at $HOME
git -C "$TMP/home/.claude" init -q  # versioned ~/.claude as its own repo
printf 'local.yml\nbuild/\n' > "$TMP/sibling/.gitignore"
touch "$TMP/home/.zshrc" "$TMP/sibling/real.yml"
ln -s "$TMP/home/.zshrc"      "$TMP/sibling/escape-link"   # link out of the repo
ln -s "$TMP/sibling/real.yml" "$TMP/sibling/inner-link"    # link within the repo
ln -s "$TMP/sibling/.env"     "$TMP/sibling/env-link"      # link to sensitive file

# Run the hook; echo allow | deny | defer
_decide() {
  local tool="$1" file="$2" out
  out="$(jq -cn --arg t "$tool" --arg f "$file" --arg cwd "$TMP/project" \
      '{tool_name:$t, session_id:"test", cwd:$cwd, tool_input:{file_path:$f}}' \
    | HOME="$TMP/home" CLAUDE_PROJECT_DIR="$TMP/project" bash "$HOOK" 2>/dev/null)"
  if [[ -z "$out" ]]; then
    echo defer
  else
    printf '%s' "$out" | jq -r '.hookSpecificOutput.decision.behavior'
  fi
}

_decide_bash() {
  local out
  out="$(jq -cn --arg c "$1" --arg cwd "$TMP/project" \
      '{tool_name:"Bash", session_id:"test", cwd:$cwd, tool_input:{command:$c}}' \
    | HOME="$TMP/home" CLAUDE_PROJECT_DIR="$TMP/project" bash "$HOOK" 2>/dev/null)"
  if [[ -z "$out" ]]; then
    echo defer
  else
    printf '%s' "$out" | jq -r '.hookSpecificOutput.decision.behavior'
  fi
}

_expect() {
  local want="$1" tool="$2" file="$3" got
  if [[ "$tool" == "Bash" ]]; then
    got="$(_decide_bash "$file")"
  else
    got="$(_decide "$tool" "$file")"
  fi
  if [[ "$got" == "$want" ]]; then
    printf "    \033[32m✓\033[0m %s %s → %s\n" "$tool" "$file" "$want"
    PASS=$((PASS+1))
  else
    printf "    \033[31m✗\033[0m %s %s\n      expected: %s\n      got:      %s\n" \
      "$tool" "$file" "$want" "$got"
    FAIL=$((FAIL+1))
  fi
}

# =============================================================================

echo "permission-request: Write/Edit paths"

suite "Project files — allow"
_expect allow Edit  "src/app.ts"
_expect allow Write "$TMP/project/new/dir/file.txt"

suite "Sibling git repo — allow"
_expect allow Edit  "../sibling/config.yml"
_expect allow Edit  "$TMP/sibling/sub/vars.yml"
_expect allow Write "$TMP/sibling/not/yet/created.txt"

suite "Sibling git repo — defer"
_expect defer Edit  "$TMP/sibling/local.yml"          # git-ignored
_expect defer Write "$TMP/sibling/build/out.js"       # git-ignored dir
_expect defer Edit  "$TMP/sibling/.git/config"        # git internals
_expect defer Write "$TMP/sibling/.git/hooks/pre-commit"

suite "Repo rooted at \$HOME / agent config — defer"
_expect defer Edit  "$TMP/home/.zshrc"
_expect defer Write "$TMP/home/.claude/settings.json"
_expect defer Edit  "$TMP/home/.claude/hooks/permission-request.sh"

suite "Non-git directory — defer"
_expect defer Edit  "$TMP/plain/notes.txt"
_expect defer Write "../plain/new.txt"

suite "Sensitive paths — deny (even in git repo)"
_expect deny Edit  "$TMP/sibling/.env"
_expect deny Write "$TMP/sibling/server.pem"

suite "Symlinks — judged by target"
_expect defer Edit "$TMP/sibling/escape-link"   # repo link → \$HOME dotfile
_expect allow Edit "$TMP/sibling/inner-link"    # repo link → same repo
_expect deny  Edit "$TMP/sibling/env-link"      # repo link → .env

suite "git rm masking — Bash"
_expect allow Bash 'git rm -r --cached build'
_expect allow Bash 'cd sub && git rm -rf old'
_expect deny  Bash 'git(){ rm "$@"; }; git rm -rf /data'
_expect deny  Bash 'function git { rm "$@"; }; git rm -rf /data'
_expect deny  Bash 'alias git=rm; git rm -rf /data'
_expect deny  Bash 'git rm a && rm -rf /data'

summary
