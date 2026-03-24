#!/usr/bin/env bash
# =============================================================================
# prompt-inject.sh — Dynamic context injection per user prompt
#
# Fires on: UserPromptSubmit
# Purpose:  Detect topic keywords in the user's prompt and inject only the
#           relevant sections from project-context.md. Avoids flooding every
#           message with the full context document.
#
# Strategy: TOPIC_PATTERNS maps keyword regex → section header in the context
#           file. When a keyword matches, that section is extracted and appended
#           as additionalContext. Multiple sections can match in one prompt.
#
# This hook NEVER blocks prompts — it only adds context or exits silently.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

HOOK_INPUT="$(read_stdin)"
USER_PROMPT="$(get_field "$HOOK_INPUT" ".prompt")"
SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"

[[ -z "$USER_PROMPT" ]] && exit 0

CONTEXT_FILE="${PROJECT_DIR}/context/project-context.md"
[[ ! -f "$CONTEXT_FILE" ]] && exit 0

# ---------------------------------------------------------------------------
# TOPIC_PATTERNS — parallel arrays for bash 3 compatibility.
# PATTERNS[i] is the keyword regex; HEADERS[i] is the matching section header.
# The section header must exactly match a markdown heading in project-context.md.
# ---------------------------------------------------------------------------
PATTERNS=(
  'deploy|deployment|release|production|staging'
  'architect|structure|design|overview|layout'
  'test|spec|coverage|jest|pytest|vitest'
  'install|setup|onboard|getting.started|run.locally'
  'api|endpoint|route|request|response|rest|graphql'
  'database|schema|migration|model|postgres|mysql|sqlite'
  'env|environment.variable|config|configuration|settings'
  'hook|hooks|safety.guard|audit.log|context.inject'
)
HEADERS=(
  "## Deployment"
  "## Architecture"
  "## Testing"
  "## Setup"
  "## API"
  "## Database"
  "## Configuration"
  "## Hook Configuration"
)

# ---------------------------------------------------------------------------
# Extract a markdown section by its header line.
# Prints from the header through the next same-level (or higher) heading.
# ---------------------------------------------------------------------------
extract_section() {
  local file="$1"
  local header="$2"
  local hashes
  hashes="$(echo "$header" | grep -oE '^#{1,6}')"

  awk -v header="$header" -v pat="^${hashes}[^#]" '
    $0 == header { found=1; print; next }
    found && $0 ~ pat { exit }
    found { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Scan prompt for keyword matches and collect relevant sections
# ---------------------------------------------------------------------------
PROMPT_LOWER="$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')"
INJECTED_SECTIONS=""

for i in "${!PATTERNS[@]}"; do
  if echo "$PROMPT_LOWER" | grep -qiE "${PATTERNS[$i]}" 2>/dev/null; then
    section_text="$(extract_section "$CONTEXT_FILE" "${HEADERS[$i]}")"
    if [[ -n "$section_text" ]]; then
      INJECTED_SECTIONS="${INJECTED_SECTIONS}

${section_text}"
    fi
  fi
done

[[ -z "$INJECTED_SECTIONS" ]] && exit 0

ADDITIONAL_CONTEXT="[Relevant project context for this prompt]:
${INJECTED_SECTIONS}"

# Log the injection
TIMESTAMP="$(iso_timestamp)"
RECORD="$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg excerpt "${USER_PROMPT:0:120}" \
  '{
    timestamp: $ts,
    session_id: $session,
    event: "UserPromptSubmit",
    context_injected: true,
    prompt_excerpt: $excerpt
  }')"
write_audit_record "$RECORD"

# Return context addition to Claude
jq -n \
  --arg context "$ADDITIONAL_CONTEXT" \
  '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $context
    }
  }'

exit 0
