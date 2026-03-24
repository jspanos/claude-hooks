#!/usr/bin/env bash
# =============================================================================
# bash-6.test.sh — Tests for bash_check_python_venv (rule bash-6)
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

# Source assert harness FIRST (installs mocks before rule is loaded)
source "$TESTS_DIR/lib/assert.sh"

# Set required globals
PROJECT_DIR="/tmp/test-project"
CWD="/tmp/test-project"
HOME="/tmp/test-home"

# Ensure the test project dir exists (but no .venv by default)
mkdir -p "$PROJECT_DIR"
rm -rf "$PROJECT_DIR/.venv"

# Source the rule under test
source "$RULES_DIR/bash-6-python-venv.sh"

# =============================================================================

echo "bash-6: Python Venv"

suite "Python venv — blocked"

# No .venv present: python3 script.py should be blocked
rm -rf "$PROJECT_DIR/.venv"
bash_check_python_venv "python3 script.py"
assert_blocked "python3 script.py (no .venv)" "bash-6"

# bare python is always blocked
bash_check_python_venv "python script.py"
assert_blocked "bare python script.py" "bash-6"

# pip install is always blocked
bash_check_python_venv "pip install requests"
assert_blocked "pip install requests" "bash-6"

bash_check_python_venv "pip3 install flask"
assert_blocked "pip3 install flask" "bash-6"

bash_check_python_venv "python3 -m pip install numpy"
assert_blocked "python3 -m pip install numpy" "bash-6"

# python -m venv when uv is available → blocked
# Mock uv as available by overriding command
command() {
  if [[ "$1" == "-v" && "$2" == "uv" ]]; then
    return 0
  fi
  builtin command "$@"
}
bash_check_python_venv "python3 -m venv .venv"
assert_blocked "python3 -m venv .venv (uv available)" "bash-6"
# Restore command
unset -f command

suite "Python venv — allowed"

bash_check_python_venv "python3 --version"
assert_allowed "python3 --version"

bash_check_python_venv "python --version"
assert_allowed "python --version"

bash_check_python_venv "uv run python3 script.py"
assert_allowed "uv run python3 script.py"

bash_check_python_venv ".venv/bin/python3 script.py"
assert_allowed ".venv/bin/python3 script.py"

# With .venv present: python3 should be allowed
mkdir -p "$PROJECT_DIR/.venv"
bash_check_python_venv "python3 script.py"
assert_allowed "python3 script.py (with .venv present)"
rm -rf "$PROJECT_DIR/.venv"

summary
