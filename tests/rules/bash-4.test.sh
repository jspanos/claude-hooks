#!/usr/bin/env bash
# =============================================================================
# bash-4.test.sh — Tests for bash_check_inline_scripts (rule bash-4)
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

# Source the rule under test
source "$RULES_DIR/bash-4-inline-scripts.sh"

# =============================================================================

echo "bash-4: Inline Scripts"

suite "Inline scripts — blocked"

bash_check_inline_scripts "cat > setup.sh << 'EOF'"
assert_blocked "heredoc to .sh" "bash-4"

bash_check_inline_scripts "echo '#!/usr/bin/env python3' > script.py"
assert_blocked "echo shebang to .py" "bash-4"

bash_check_inline_scripts "bash -c 'a; b; c; d; e'"
assert_blocked "bash -c with 4+ commands" "bash-4"

# Build a 200+ character inline python string
long_code="$(python3 -c "print('x' * 200)")"
bash_check_inline_scripts "python3 -c '$long_code'"
assert_blocked "large python -c (200+ chars)" "bash-4"

suite "Inline scripts — allowed"

bash_check_inline_scripts "bash -c 'echo hello'"
assert_allowed "bash -c with only 1 command"

bash_check_inline_scripts "bash -c 'a; b; c'"
assert_allowed "bash -c with 3 separators (below threshold)"

bash_check_inline_scripts "python3 -c 'print(1)'"
assert_allowed "python3 -c with short code"

bash_check_inline_scripts "npm install"
assert_allowed "normal command (npm install)"

summary
