#!/usr/bin/env bash
# =============================================================================
# bash-2.test.sh — Tests for bash_check_uncommitted_files (rule bash-2)
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

# Source assert harness FIRST (installs mocks before rule is loaded)
source "$TESTS_DIR/lib/assert.sh"

# Set required globals
PROJECT_DIR="/home/testuser/myproject"
CWD="/home/testuser/myproject"
HOME="/home/testuser"

# Mock git: controlled output via GIT_MOCK_STATUS variable
# Real git -C ... rev-parse succeeds (we're "in a git repo")
# Real git -C ... status --porcelain returns GIT_MOCK_STATUS
GIT_MOCK_STATUS=""
git() {
  # git -C <dir> rev-parse --git-dir → succeed (simulate a git repo)
  if [[ "$*" == *"rev-parse"* ]]; then
    return 0
  fi
  # git -C <dir> status --porcelain -- <file> → return mock status
  if [[ "$*" == *"status"* ]]; then
    printf '%s\n' "$GIT_MOCK_STATUS"
    return 0
  fi
  command git "$@"
}

# Source the rule under test
source "$RULES_DIR/bash-2-uncommitted-files.sh"

# =============================================================================

echo "bash-2: Uncommitted Files"

suite "Uncommitted files — blocked"

GIT_MOCK_STATUS=" M file.txt"
bash_check_uncommitted_files "rm file.txt"
assert_blocked "rm on modified file" "bash-2"

GIT_MOCK_STATUS="M  file.txt"
bash_check_uncommitted_files "echo hello > file.txt"
assert_blocked "output redirect on staged file" "bash-2"

GIT_MOCK_STATUS="?? file.txt"
bash_check_uncommitted_files "sed -i 's/foo/bar/' file.txt"
assert_blocked "sed -i on untracked file" "bash-2"

suite "Uncommitted files — allowed"

GIT_MOCK_STATUS=""
bash_check_uncommitted_files "rm file.txt"
assert_allowed "rm on committed file (no git status)"

bash_check_uncommitted_files "rm /etc/hosts"
assert_allowed "rm on file outside project"

bash_check_uncommitted_files "rm *.txt"
assert_allowed "rm with glob pattern (skipped)"

summary
