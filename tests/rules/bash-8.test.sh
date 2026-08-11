#!/usr/bin/env bash
# =============================================================================
# bash-8.test.sh — Tests for bash_check_interpreter_file_ops (rule bash-8)
#
# These cover the bypass that motivated the rule: short interpreter one-liners
# that mutate files without ever naming rm/mv in the shell command.
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/rules" && pwd)"

source "$TESTS_DIR/lib/assert.sh"

PROJECT_DIR="/home/testuser/myproject"
CWD="/home/testuser/myproject"
HOME="/home/testuser"

source "$RULES_DIR/bash-8-interpreter-file-ops.sh"

# =============================================================================

echo "bash-8: Interpreter File Operations"

suite "Python file mutation — blocked"

bash_check_interpreter_file_ops "python3 -c \"import os; os.remove('a.txt')\""
assert_blocked "python3 -c os.remove" "bash-8"

bash_check_interpreter_file_ops "uv run python3 -c \"import os; os.remove('a.txt')\""
assert_blocked "uv run python3 -c os.remove (bash-6 allowlisted prefix)" "bash-8"

bash_check_interpreter_file_ops ".venv/bin/python3 -c \"import shutil; shutil.rmtree('.claude')\""
assert_blocked ".venv/bin/python3 -c shutil.rmtree" "bash-8"

bash_check_interpreter_file_ops "python3 -c \"import pathlib; pathlib.Path('.env').write_text('x')\""
assert_blocked "python3 -c Path.write_text" "bash-8"

bash_check_interpreter_file_ops "python3 -c \"open('notes.md', 'w').write('')\""
assert_blocked "python3 -c open(...,'w')" "bash-8"

bash_check_interpreter_file_ops "python3 -c \"import os; os.rename('a','b')\""
assert_blocked "python3 -c os.rename" "bash-8"

suite "Other interpreters — blocked"

bash_check_interpreter_file_ops "node -e \"require('fs').unlinkSync('CLAUDE.md')\""
assert_blocked "node -e fs.unlinkSync" "bash-8"

bash_check_interpreter_file_ops "node -e \"require('fs').writeFileSync('a','')\""
assert_blocked "node -e fs.writeFileSync" "bash-8"

bash_check_interpreter_file_ops "ruby -e \"File.delete('CLAUDE.md')\""
assert_blocked "ruby -e File.delete" "bash-8"

bash_check_interpreter_file_ops "ruby -e \"FileUtils.rm_rf('.claude')\""
assert_blocked "ruby -e FileUtils.rm_rf" "bash-8"

suite "Shelling out from an interpreter — blocked"

bash_check_interpreter_file_ops "python3 -c \"import os; os.system('rm -rf build')\""
assert_blocked "python3 -c os.system (re-enters shell past bash rules)" "bash-8"

bash_check_interpreter_file_ops "python3 -c \"import subprocess; subprocess.run(['rm','x'])\""
assert_blocked "python3 -c subprocess.run" "bash-8"

bash_check_interpreter_file_ops "node -e \"require('child_process').execSync('rm x')\""
assert_blocked "node -e child_process.execSync" "bash-8"

suite "Heredoc into an interpreter — blocked"

bash_check_interpreter_file_ops "python3 << 'EOF'
print(1)
EOF"
assert_blocked "python3 << EOF heredoc" "bash-8"

suite "Read-only / harmless interpreter use — allowed"

bash_check_interpreter_file_ops "python3 -c \"print(1+1)\""
assert_allowed "python3 -c arithmetic"

bash_check_interpreter_file_ops "python3 -c \"print(open('a.txt').read())\""
assert_allowed "python3 -c reading a file"

bash_check_interpreter_file_ops "python3 -c \"import json; print(json.dumps({'a':1}))\""
assert_allowed "python3 -c json dump to stdout"

bash_check_interpreter_file_ops "node -e \"console.log(process.version)\""
assert_allowed "node -e printing version"

bash_check_interpreter_file_ops "python3 script.py"
assert_allowed "python3 running a script file (not inline)"

bash_check_interpreter_file_ops "rm a.txt"
assert_allowed "plain rm (bash-2's job, not this rule's)"

summary
