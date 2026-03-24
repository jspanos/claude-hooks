#!/usr/bin/env bash
# =============================================================================
# file-1.test.sh — Tests for file_check_sensitive_path (rule file-1)
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

# Source the rule under test
source "$RULES_DIR/file-1-sensitive-paths.sh"

# =============================================================================

echo "file-1: Sensitive Paths"

suite "Sensitive paths — blocked"

file_check_sensitive_path ".env"
assert_blocked ".env" "file-1"

file_check_sensitive_path ".env.production"
assert_blocked ".env.production" "file-1"

# .env.example also matches '(^|/)\.env(\.[a-zA-Z]+)?$' — .example is \.[a-zA-Z]+
file_check_sensitive_path ".env.example"
assert_blocked ".env.example (matches regex)" "file-1"

file_check_sensitive_path "secrets/api_key.json"
assert_blocked "secrets/api_key.json" "file-1"

file_check_sensitive_path "server.pem"
assert_blocked "server.pem" "file-1"

file_check_sensitive_path ".ssh/id_rsa"
assert_blocked ".ssh/id_rsa" "file-1"

file_check_sensitive_path ".kube/config"
assert_blocked ".kube/config" "file-1"

file_check_sensitive_path ".docker/config.json"
assert_blocked ".docker/config.json" "file-1"

file_check_sensitive_path "terraform.tfstate"
assert_blocked "terraform.tfstate" "file-1"

suite "Sensitive paths — allowed"

file_check_sensitive_path "src/app.ts"
assert_allowed "src/app.ts"

file_check_sensitive_path "README.md"
assert_allowed "README.md"

file_check_sensitive_path "package.json"
assert_allowed "package.json"

file_check_sensitive_path ".github/workflows/ci.yml"
assert_allowed ".github/workflows/ci.yml"

summary
