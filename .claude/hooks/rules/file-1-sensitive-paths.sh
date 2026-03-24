# =============================================================================
# file-1-sensitive-paths.sh — Rule: Protect sensitive file paths from Write/Edit
# =============================================================================

file_check_sensitive_path() {
  local file_path="$1"

  local -a SENSITIVE=(
    '(^|/)\.env(\.[a-zA-Z]+)?$'
    '\.(pem|key|p12|pfx|crt|cer|der)$'
    '(^|/)\.ssh/'
    '(secret|credential|password|passwd|token|apikey|api_key)(s)?\.(json|yaml|yml|toml|ini|conf|txt)$'
    '(^|/)\.(aws|gcp|azure)/(credentials|config|key)$'
    '\.(gpg|pgp|asc)$'
    '\.(keychain|keychain-db)$'
    '\.(kdbx|kdb)$'
    '(^|/)\.(netrc|npmrc|pypirc|gitcredentials)$'
    'terraform\.tfstate(\.backup)?$'
    '(^|/)\.kube/config$'
    '(^|/)\.docker/config\.json$'
  )

  for pat in "${SENSITIVE[@]}"; do
    if printf '%s' "$file_path" | grep -qiE "$pat"; then
      deny_and_log "file-1" \
        "Write to '$file_path' blocked — matches sensitive file pattern '$pat'. Update SENSITIVE array in .claude/hooks/pre-tool-use.sh to allow if intentional."
    fi
  done
}
