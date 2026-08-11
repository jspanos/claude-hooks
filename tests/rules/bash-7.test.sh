#!/usr/bin/env bash
# =============================================================================
# bash-7.test.sh — Tests for bash_check_protected_config (rule bash-7)
#
# Covers shell-side attempts to disable the enforcement layer, including the
# forms that hide the target behind `cd` or a pipeline boundary.
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks" && pwd)"

source "$TESTS_DIR/lib/assert.sh"

PROJECT_DIR="/home/testuser/myproject"   # no .claude-hooks-source → guarded
CWD="/home/testuser/myproject"
HOME="/home/testuser"

source "$HOOKS_DIR/lib/protected-paths.sh"
source "$HOOKS_DIR/lib/mutation-targets.sh"
source "$HOOKS_DIR/rules/bash-7-protected-config.sh"

# =============================================================================

echo "bash-7: Protected Hook Config"

suite "Disabling hooks from the shell — blocked"

bash_check_protected_config "rm .claude/hooks/rules/bash-5-pipe-abuse.sh"
assert_blocked "rm a rule file" "bash-7"

bash_check_protected_config "rm -rf .claude/hooks"
assert_blocked "rm -rf the hooks directory" "bash-7"

bash_check_protected_config "cd .claude && rm settings.json"
assert_blocked "cd .claude && rm settings.json (cd-prefixed)" "bash-7"

bash_check_protected_config "mv .claude/hooks /tmp/stashed"
assert_blocked "mv the hooks directory away" "bash-7"

bash_check_protected_config "echo '{}' > .claude/settings.json"
assert_blocked "truncate settings.json via redirect" "bash-7"

bash_check_protected_config "cp /dev/null .claude/hooks/pre-tool-use.sh"
assert_blocked "cp /dev/null over the dispatcher" "bash-7"

bash_check_protected_config "chmod -x .claude/hooks/pre-tool-use.sh"
assert_blocked "chmod -x the dispatcher (metadata attack)" "bash-7"

bash_check_protected_config "sed -i 's/deny/allow/' .claude/hooks/rules/file-1-sensitive-paths.sh"
assert_blocked "sed -i a rule file" "bash-7"

bash_check_protected_config "touch .claude-hooks-source > .claude-hooks-source"
assert_blocked "creating the self-edit marker" "bash-7"

bash_check_protected_config "rm /home/testuser/.claude/hooks/rules/bash-1-absolute-paths.sh"
assert_blocked "rm a globally deployed rule" "bash-7"

suite "Ordinary project work — allowed"

bash_check_protected_config "rm src/index.ts"
assert_allowed "rm an ordinary source file"

bash_check_protected_config "cat .claude/settings.json"
assert_allowed "reading settings.json"

bash_check_protected_config "ls .claude/hooks/rules"
assert_allowed "listing the rules directory"

bash_check_protected_config "grep -r deny .claude/hooks"
assert_allowed "grepping the hooks directory"

bash_check_protected_config "rm .claude/logs/audit.jsonl"
assert_allowed "rm the audit log (not enforcement code)"

suite "Hooks source repo — exempt"

MARKER_REPO="$(mktemp -d)"
touch "$MARKER_REPO/.claude-hooks-source"
_SAVED_PROJECT_DIR="$PROJECT_DIR"
PROJECT_DIR="$MARKER_REPO"
CWD="$MARKER_REPO"

bash_check_protected_config "rm .claude/hooks/rules/bash-5-pipe-abuse.sh"
assert_allowed "rm a rule file inside the hooks source repo"

PROJECT_DIR="$_SAVED_PROJECT_DIR"
CWD="$PROJECT_DIR"
rm -rf "$MARKER_REPO"

summary
