#!/usr/bin/env bash
# =============================================================================
# pre-tool-bash-guard.sh — Safety guard for Bash tool calls
#
# Fires on: PreToolUse (matcher: "Bash")
# Purpose:  Block dangerous shell commands before they execute.
#
# CONFIGURATION:
#   Edit BLOCKED_PATTERNS to add/remove patterns (Perl-compatible regex).
#   Edit ALLOWED_PREFIXES for known-safe commands that match blocked patterns.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

# ---------------------------------------------------------------------------
# BLOCKED_PATTERNS — Perl-compatible regex, case-insensitive.
# Any command matching one of these is denied.
# ---------------------------------------------------------------------------
BLOCKED_PATTERNS=(
  # Recursive force deletion
  'rm\s+(-[^\s]*[rR][^\s]*[fF]|-[^\s]*[fF][^\s]*[rR]|--force\s+--recursive|--recursive\s+--force|-rf|-fr)'
  # Git force push to protected branches (but not --force-with-lease)
  'git\s+push\s+(?!.*--force-with-lease).*(-f|--force).*\s(origin\s+)?(main|master|production|prod|release)\b'
  # Pipe internet content directly to shell
  '(curl|wget)\s+.*\|\s*(sudo\s+)?(ba)?sh\b'
  # chmod world-writable on system paths
  'chmod\s+(777|a\+w|o\+w)\s+.*(\/etc|\/bin|\/usr|\/lib|\/boot)'
  # Direct overwrite of /etc files
  '>\s*\/etc\/(?!hosts\.bak)'
  # Kill all processes
  'kill\s+-9\s+-1|pkill\s+-9\s+-1'
  # Fork bomb
  ':\s*\(\s*\)\s*\{'
  # Overwrite raw disk devices
  'dd\s+.*of=\/dev\/(sd[a-z]|nvme\d|disk\d)[^p]'
  # Disable firewall
  '\bufw\s+disable\b|pfctl\s+-d\b'
)

# ---------------------------------------------------------------------------
# ALLOWED_PREFIXES — commands starting with these bypass the block list.
# ---------------------------------------------------------------------------
ALLOWED_PREFIXES=(
  "echo"
  "printf"
  "git push --force-with-lease"
)

# ---------------------------------------------------------------------------
# Read input
# ---------------------------------------------------------------------------
HOOK_INPUT="$(read_stdin)"
COMMAND="$(get_field "$HOOK_INPUT" ".tool_input.command")"

[[ -z "$COMMAND" ]] && exit 0

# ---------------------------------------------------------------------------
# Allow-list check
# ---------------------------------------------------------------------------
for prefix in "${ALLOWED_PREFIXES[@]}"; do
  if [[ "$COMMAND" == "$prefix"* ]]; then
    exit 0
  fi
done

# ---------------------------------------------------------------------------
# Block-list check
# ---------------------------------------------------------------------------
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | perl -ne "exit(m{$pattern}i ? 0 : 1)" 2>/dev/null; then
    # Log the blocked attempt
    TIMESTAMP="$(iso_timestamp)"
    SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"
    RECORD="$(jq -cn \
      --arg ts "$TIMESTAMP" \
      --arg session "$SESSION_ID" \
      --arg cmd "$COMMAND" \
      --arg pattern "$pattern" \
      '{
        timestamp: $ts,
        session_id: $session,
        event: "PreToolUse",
        tool_name: "Bash",
        blocked: true,
        reason: "matched_safety_pattern",
        pattern: $pattern,
        command: $cmd
      }')"
    write_audit_record "$RECORD"

    deny_tool_use "Blocked by safety guard — command matched dangerous pattern: '${pattern}'. To allow, update BLOCKED_PATTERNS in .claude/hooks/safety/pre-tool-bash-guard.sh"
  fi
done

exit 0
