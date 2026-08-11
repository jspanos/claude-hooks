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

# Source the shared target extractor, then the rule under test
source "$(cd "$RULES_DIR/.." && pwd)/lib/mutation-targets.sh"
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

suite "Mutators previously unmodelled — blocked"

GIT_MOCK_STATUS=" M settings.json"
bash_check_uncommitted_files "cd .claude && rm settings.json"
assert_blocked "rm hidden behind a cd prefix" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "cp /dev/null CLAUDE.md"
assert_blocked "cp overwriting the destination" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "git checkout -- CLAUDE.md"
assert_blocked "git checkout discarding changes" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "git restore CLAUDE.md"
assert_blocked "git restore discarding changes" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "install -m 644 /dev/null CLAUDE.md"
assert_blocked "install overwriting the destination" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "ln -sf /dev/null CLAUDE.md"
assert_blocked "ln -sf clobbering a file" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "ed -s CLAUDE.md"
assert_blocked "ed in-place edit" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "echo x | tee CLAUDE.md"
assert_blocked "tee overwrite after a pipe" "bash-2"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "git reset --hard HEAD"
assert_blocked "git reset --hard with a dirty tree" "bash-2"

GIT_MOCK_STATUS="?? scratch.txt"
bash_check_uncommitted_files "git clean -fdx"
assert_blocked "git clean -fdx with untracked files" "bash-2"

suite "Uncommitted files — allowed"

GIT_MOCK_STATUS=""
bash_check_uncommitted_files "cd .claude && rm settings.json"
assert_allowed "cd-prefixed rm on a clean file"

GIT_MOCK_STATUS=""
bash_check_uncommitted_files "git reset --hard HEAD"
assert_allowed "git reset --hard on a clean tree"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "git checkout main"
assert_allowed "git checkout switching branches (no path operand)"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "ln -s target linkname"
assert_allowed "ln -s without -f (cannot clobber)"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "echo x >> CLAUDE.md"
assert_allowed "append redirect (>> does not truncate)"

GIT_MOCK_STATUS=" M CLAUDE.md"
bash_check_uncommitted_files "cat CLAUDE.md"
assert_allowed "reading a modified file"


GIT_MOCK_STATUS=""
bash_check_uncommitted_files "rm file.txt"
assert_allowed "rm on committed file (no git status)"

bash_check_uncommitted_files "rm /etc/hosts"
assert_allowed "rm on file outside project"

bash_check_uncommitted_files "rm *.txt"
assert_allowed "rm with glob pattern (skipped)"

summary
