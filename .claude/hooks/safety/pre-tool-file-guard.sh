#!/usr/bin/env bash
# =============================================================================
# pre-tool-file-guard.sh — Safety guard for Write and Edit tool calls
#
# Fires on: PreToolUse (matcher: "Write|Edit")
# Purpose:  Prevent writes to sensitive files: credentials, keys, env configs.
#
# CONFIGURATION:
#   Edit SENSITIVE_PATH_PATTERNS to add/remove protected path patterns.
#   Patterns are extended regex (ERE), case-insensitive, matched against the
#   full file_path string from the tool input.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

# ---------------------------------------------------------------------------
# SENSITIVE_PATH_PATTERNS — ERE, case-insensitive.
# ---------------------------------------------------------------------------
SENSITIVE_PATH_PATTERNS=(
  # Environment variable files
  '(^|/)\.env(\.[a-z]+)?$'
  # Private keys and certificates
  '\.(pem|key|p12|pfx|crt|cer|der)$'
  # SSH directory
  '(^|/)\.ssh/'
  # Generic secret naming conventions
  '(secret|credential|password|passwd|token|apikey|api_key)(s)?\.(json|yaml|yml|toml|ini|conf|txt)$'
  # Cloud provider credential files
  '(^|/)\.(aws|gcp|azure)/(credentials|config|key)$'
  # GPG/PGP files
  '\.(gpg|pgp|asc)$'
  # macOS keychain
  '\.(keychain|keychain-db)$'
  # KeePass databases
  '\.(kdbx|kdb)$'
  # Dotfiles that often contain tokens
  '(^|/)\.(netrc|npmrc|pypirc|gitcredentials)$'
  # Terraform state (can contain secrets)
  'terraform\.tfstate(\.backup)?$'
  # kubeconfig
  '(^|/)\.kube/config$'
  # Docker config with registry auth
  '(^|/)\.docker/config\.json$'
)

# ---------------------------------------------------------------------------
# Read input
# ---------------------------------------------------------------------------
HOOK_INPUT="$(read_stdin)"
FILE_PATH="$(get_field "$HOOK_INPUT" ".tool_input.file_path")"
TOOL_NAME="$(get_field "$HOOK_INPUT" ".tool_name")"

[[ -z "$FILE_PATH" ]] && exit 0

# ---------------------------------------------------------------------------
# Check file path against sensitive patterns
# ---------------------------------------------------------------------------
for pattern in "${SENSITIVE_PATH_PATTERNS[@]}"; do
  if echo "$FILE_PATH" | grep -qiE "$pattern" 2>/dev/null; then
    TIMESTAMP="$(iso_timestamp)"
    SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"
    RECORD="$(jq -cn \
      --arg ts "$TIMESTAMP" \
      --arg session "$SESSION_ID" \
      --arg tool "$TOOL_NAME" \
      --arg path "$FILE_PATH" \
      --arg pattern "$pattern" \
      '{
        timestamp: $ts,
        session_id: $session,
        event: "PreToolUse",
        tool_name: $tool,
        blocked: true,
        reason: "sensitive_file_path",
        pattern: $pattern,
        file_path: $path
      }')"
    write_audit_record "$RECORD"

    deny_tool_use "Blocked: '${FILE_PATH}' matches sensitive file pattern '${pattern}'. To allow, update SENSITIVE_PATH_PATTERNS in .claude/hooks/safety/pre-tool-file-guard.sh"
  fi
done

exit 0
