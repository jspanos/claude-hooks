#!/usr/bin/env bash
# =============================================================================
# file-2.test.sh — Tests for file_check_protected_config (rule file-2)
#
# The Write/Edit counterpart to bash-7: without it, an agent blocked from
# deleting a rule file could simply overwrite it with a no-op.
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks" && pwd)"

source "$TESTS_DIR/lib/assert.sh"

PROJECT_DIR="/home/testuser/myproject"   # no .claude-hooks-source → guarded
CWD="/home/testuser/myproject"
HOME="/home/testuser"

source "$HOOKS_DIR/lib/protected-paths.sh"
source "$HOOKS_DIR/rules/file-2-protected-config.sh"

# =============================================================================

echo "file-2: Protected Hook Config (Write/Edit)"

suite "Writing to the enforcement layer — blocked"

file_check_protected_config ".claude/hooks/rules/bash-5-pipe-abuse.sh"
assert_blocked "overwrite a rule file" "file-2"

file_check_protected_config ".claude/hooks/pre-tool-use.sh"
assert_blocked "overwrite the dispatcher" "file-2"

file_check_protected_config ".claude/hooks/lib/common.sh"
assert_blocked "overwrite the shared library" "file-2"

file_check_protected_config ".claude/settings.json"
assert_blocked "rewrite hook wiring" "file-2"

file_check_protected_config ".claude/settings.local.json"
assert_blocked "rewrite local hook wiring" "file-2"

file_check_protected_config "/home/testuser/.claude/hooks/rules/bash-1-absolute-paths.sh"
assert_blocked "overwrite a globally deployed rule" "file-2"

file_check_protected_config ".claude-hooks-source"
assert_blocked "create the self-edit marker (no self-authorising)" "file-2"

suite "Ordinary files — allowed"

file_check_protected_config "src/index.ts"
assert_allowed "an ordinary source file"

file_check_protected_config "CLAUDE.md"
assert_allowed "CLAUDE.md (advisory, not enforcement)"

file_check_protected_config ".claude/CLAUDE.md"
assert_allowed ".claude/CLAUDE.md (advisory, not enforcement)"

file_check_protected_config "scripts/deploy.sh"
assert_allowed "a project script"

file_check_protected_config "tests/rules/bash-1.test.sh"
assert_allowed "a test file"

suite "Hooks source repo — exempt"

MARKER_REPO="$(mktemp -d)"
touch "$MARKER_REPO/.claude-hooks-source"
_SAVED_PROJECT_DIR="$PROJECT_DIR"
PROJECT_DIR="$MARKER_REPO"

file_check_protected_config ".claude/hooks/rules/bash-5-pipe-abuse.sh"
assert_allowed "overwrite a rule file inside the hooks source repo"

PROJECT_DIR="$_SAVED_PROJECT_DIR"
rm -rf "$MARKER_REPO"

summary
