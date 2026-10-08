#!/usr/bin/env bash
# =============================================================================
# bash-10.test.sh — Tests for bash_check_quoted_newline_hash (rule bash-10)
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

# Source assert harness FIRST (installs mocks before rule is loaded)
source "$TESTS_DIR/lib/assert.sh"

PROJECT_DIR="/home/testuser/myproject"
CWD="/home/testuser/myproject"
HOME="/home/testuser"

source "$RULES_DIR/bash-10-quoted-newline-hash.sh"

NL=$'\n'

# =============================================================================

echo "bash-10: Newline + # in quoted argument"

suite "Quoted newline-hash — blocked"

bash_check_quoted_newline_hash "gh pr create --title \"t\" --body \"## Summary${NL}Fix it.${NL}${NL}## Details${NL}none\""
assert_blocked "gh pr create --body with markdown headings" "bash-10"

bash_check_quoted_newline_hash "git push -q 2>&1 | tail -1; gh pr create --body \"intro${NL}## Summary\" | tail -1"
assert_blocked "heading after first line, chained command" "bash-10"

bash_check_quoted_newline_hash "gh issue create --body 'text${NL}# Heading'"
assert_blocked "single-quoted body" "bash-10"

bash_check_quoted_newline_hash "git commit -m \"subject${NL}${NL}  # indented hash\""
assert_blocked "git commit -m with indented # line" "bash-10"

bash_check_quoted_newline_hash "gh pr edit 3 --body \"say \\\"hi\\\"${NL}## Notes\""
assert_blocked "escaped quotes inside double-quoted body" "bash-10"

bash_check_quoted_newline_hash "echo \"a${NL}#b\""
assert_blocked "any command, not only gh/git" "bash-10"

suite "Quoted newline-hash — allowed"

bash_check_quoted_newline_hash "gh pr create --title t --body-file pr-body.md"
assert_allowed "gh pr create --body-file"

bash_check_quoted_newline_hash "gh pr create --body \"Summary${NL}Closes #19\""
assert_allowed "# mid-line in body (Closes #19)"

bash_check_quoted_newline_hash "git commit -m \"fix #12: handle empty input\""
assert_allowed "single-line message with #"

bash_check_quoted_newline_hash "ls${NL}# a real shell comment${NL}pwd"
assert_allowed "unquoted shell comment line"

bash_check_quoted_newline_hash "ls # it's a comment with an apostrophe${NL}echo \"ok\""
assert_allowed "apostrophe inside a comment does not open a quote"

bash_check_quoted_newline_hash "echo \"line1${NL}line2\""
assert_allowed "multi-line quoted string without #"

bash_check_quoted_newline_hash "echo \"a\"${NL}# comment after closing quote"
assert_allowed "comment line after quote closes"

summary
