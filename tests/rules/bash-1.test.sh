#!/usr/bin/env bash
# =============================================================================
# bash-1.test.sh — Tests for bash_check_absolute_paths (rule bash-1)
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

# Source assert harness FIRST (installs mocks before rule is loaded)
source "$TESTS_DIR/lib/assert.sh"

# Set required globals — must NOT be under system prefixes like /tmp, /usr, /var etc.
# The rule treats /tmp/* as a system path, so use a non-system path.
PROJECT_DIR="/home/testuser/myproject"
CWD="/home/testuser/myproject"
HOME="/home/testuser"

# Source the rule under test
source "$RULES_DIR/bash-1-absolute-paths.sh"

# =============================================================================

echo "bash-1: Absolute Paths"

suite "Absolute paths — blocked"

bash_check_absolute_paths "cat /home/testuser/myproject/src/file.txt"
assert_blocked "absolute path inside PROJECT_DIR" "bash-1"

bash_check_absolute_paths "/home/testuser/secret.txt"
assert_blocked "absolute path inside HOME" "bash-1"

suite "Absolute paths — allowed"

bash_check_absolute_paths "cat ./src/file.txt"
assert_allowed "relative path"

bash_check_absolute_paths "/usr/bin/env python3"
assert_allowed "system path /usr/bin/env"

bash_check_absolute_paths "ls /tmp/foo"
assert_allowed "system path /tmp"

bash_check_absolute_paths "cmd > /dev/null"
assert_allowed "/dev/null"

bash_check_absolute_paths "/opt/homebrew/bin/jq"
assert_allowed "homebrew path"

summary
