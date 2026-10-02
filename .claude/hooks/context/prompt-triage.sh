#!/usr/bin/env bash
# =============================================================================
# prompt-triage.sh — Gate expensive work behind a short discovery interview
#
# Fires on: UserPromptSubmit
# Purpose:  Classify the prompt's task type and score how well specified it is.
#           When an EXPENSIVE task arrives UNDERSPECIFIED, inject the matching
#           slot checklist and instruct Claude to interview before acting.
#           When the prompt is already well formed, inject NOTHING — this hook
#           costs zero tokens on good prompts by design.
#
# Never blocks. Pure bash + grep; no model calls, no network.
#
# Slot definitions: .claude/prompts/task-slots.md (one "## <type>" per type),
#                   resolved as ../../prompts/ from this script. deploy.sh
#                   installs it alongside the hooks.
# Disable:          export CLAUDE_PROMPT_TRIAGE=0
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_jq

[[ "${CLAUDE_PROMPT_TRIAGE:-1}" == "0" ]] && exit 0

HOOK_INPUT="$(read_stdin)"
USER_PROMPT="$(get_field "$HOOK_INPUT" ".prompt")"
SESSION_ID="$(get_field "$HOOK_INPUT" ".session_id")"

[[ -z "$USER_PROMPT" ]] && exit 0

SLOTS_FILE="${SCRIPT_DIR}/../../prompts/task-slots.md"
[[ -f "$SLOTS_FILE" ]] || exit 0

P="$(printf '%s' "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')"

# ---------------------------------------------------------------------------
# Bypasses — the user has signalled they don't want to be asked, the prompt is
# a command, or it's a mid-task refinement rather than a fresh task.
# ---------------------------------------------------------------------------
case "$USER_PROMPT" in
  /*|!*|@*) exit 0 ;;
esac

# Explicit opt-out, or an answer to something already in flight
if printf '%s' "$P" | grep -qiE "just do it|no questions|don'?t ask|dont ask|stop asking|go ahead|proceed|yolo|you decide|as discussed|per the plan|skip the interview"; then
  exit 0
fi

# Continuation of work already scoped earlier in the session
if printf '%s' "$P" | grep -qiE "^(also|now|next|then|and |but |ok|okay|yes|no|continue|keep going|carry on|same |that |it )"; then
  exit 0
fi

WORDS="$(printf '%s' "$USER_PROMPT" | wc -w | tr -d ' ')"

# ---------------------------------------------------------------------------
# Task classification — first match wins, ordered most specific first.
# ---------------------------------------------------------------------------
TYPE=""
classify() {
  printf '%s' "$P" | grep -qiE "$1" && TYPE="$2"
}
[[ -z "$TYPE" ]] && classify "terraform|kubernetes|k8s|helm|flux|ansible|deploy|rollout|dns|firewall|pfsense|vlan|ingress|cluster|infra|pipeline|runner|cert|secret rotation" "ops"
[[ -z "$TYPE" ]] && classify "traceback|stack trace|exception|segfault|panic:|exit code|regress|broken|crash|fails?|failing|not work|doesn'?t work|does not work|bug|why is|why does|why isn'?t|root ?cause|rca" "debug"
[[ -z "$TYPE" ]] && classify "compare|evaluate|tradeoff|trade-off|pros and cons|which (one|should|is better)|should (we|i) (use|pick|choose|adopt)|options for|investigate whether|worth it" "research"
[[ -z "$TYPE" ]] && classify "refactor|clean ?up|restructure|reorganiz|extract|dedupe|de-duplicate|simplify|modernize|migrate|rewrite|rename .* (to|across)" "refactor"
[[ -z "$TYPE" ]] && classify "implement|build|create|add (a|an|support|the)?|new (endpoint|feature|command|page|service|field)|feature|support for|wire up|hook up" "feature"

# Cheap types: explain / review / tests are never gated. Named here only so the
# classifier doesn't fall through to an expensive type by accident.
[[ -z "$TYPE" ]] && classify "explain|how does|what does|walk me through|understand|onboard|summariz|document|review|audit|critique|write tests?|add tests?|unit test|coverage" "cheap"

# Unclassified or cheap → nothing to do
case "$TYPE" in
  ""|cheap) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Specification scoring — each satisfied signal is +1.
# ---------------------------------------------------------------------------
SCORE=0
MISSING=""

add() { SCORE=$((SCORE + 1)); }
miss() { MISSING="${MISSING}${MISSING:+, }$1"; }

# A concrete location to act on
if printf '%s' "$USER_PROMPT" | grep -qE "[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|py|go|rs|rb|java|kt|swift|c|h|cpp|cs|php|tf|ya?ml|json|toml|sh|sql|md|proto)|(^|[[:space:]])(src|lib|app|pkg|cmd|internal|api|services?|components?|modules?)/"; then add; else miss "target files or paths"; fi

# A definition of done
if printf '%s' "$P" | grep -qiE "should|must|expect|so that|acceptance|criteri|definition of done|success looks|when .* then|end state"; then add; else miss "acceptance criteria / definition of done"; fi

# A scope fence
if printf '%s' "$P" | grep -qiE "only|don'?t|do not|avoid|instead of|limit(ed)? to|scope|without (changing|touching)|leave .* (alone|as is)|out of scope"; then add; else miss "scope boundary (what NOT to touch)"; fi

# Enough words to carry intent
if [[ "$WORDS" -ge 30 ]]; then add; else miss "detail (prompt is ${WORDS} words)"; fi

# A pointer to prior context
if printf '%s' "$USER_PROMPT" | grep -qE "#[0-9]+|\b[EF][0-9]{4,}\b|ticket|issue|jira|rally|PR |pull request|RFC|design doc|spec"; then add; fi

# Type-specific hard requirement
case "$TYPE" in
  debug)
    if printf '%s' "$USER_PROMPT" | grep -qE '```|Error|Exception|Traceback|assert|expected .* (but|got)|exit code|[0-9]{3} (error|response)'; then add; else miss "the actual error text or a repro"; fi
    ;;
  research)
    if printf '%s' "$P" | grep -qiE "constraint|budget|requirement|must support|we need|deadline|criteria"; then add; else miss "the decision criteria that would settle it"; fi
    ;;
  ops)
    if printf '%s' "$P" | grep -qiE "staging|prod|production|dev|test env|environment|dry.?run|rollback|blast radius"; then add; else miss "target environment and rollback expectation"; fi
    ;;
esac

# ---------------------------------------------------------------------------
# Threshold: well-specified prompts pass through silently.
# ---------------------------------------------------------------------------
THRESHOLD="${CLAUDE_PROMPT_TRIAGE_THRESHOLD:-3}"
[[ "$SCORE" -ge "$THRESHOLD" ]] && exit 0

# ---------------------------------------------------------------------------
# Extract the slot checklist for this task type.
# ---------------------------------------------------------------------------
SLOTS="$(awk -v h="## ${TYPE}" '$0 == h {f=1; next} f && /^## / {exit} f {print}' "$SLOTS_FILE")"

ADDITIONAL_CONTEXT="[prompt-triage] Task type: ${TYPE}. Specification score: ${SCORE}/${THRESHOLD}.

This prompt is underspecified for work of this cost. Before editing files, running commands, or committing to an approach:

1. Resolve what you can yourself — read the code, check config, run a search. Never ask for something the repo can answer.
2. Then ask ONLY about what is genuinely undecidable from the codebase, using a SINGLE AskUserQuestion call with at most 4 questions batched together. Lead each with your recommended option, marked \"(Recommended)\".
3. If everything resolved from step 1, skip asking and state your assumptions in one line instead.

Likely gaps in this prompt: ${MISSING:-none detected}

Slot checklist for ${TYPE}:
${SLOTS}

Do not restate this checklist to the user. Do not interview past 4 questions — for deeper design work, suggest /grill-me. If the user says to just proceed, proceed."

# Log
RECORD="$(jq -cn \
  --arg ts "$(iso_timestamp)" \
  --arg session "$SESSION_ID" \
  --arg type "$TYPE" \
  --arg score "$SCORE" \
  --arg missing "$MISSING" \
  --arg excerpt "${USER_PROMPT:0:120}" \
  '{
    timestamp: $ts,
    session_id: $session,
    event: "UserPromptSubmit",
    hook: "prompt-triage",
    task_type: $type,
    spec_score: ($score | tonumber),
    missing: $missing,
    prompt_excerpt: $excerpt
  }')"
write_audit_record "$RECORD"

jq -n \
  --arg context "$ADDITIONAL_CONTEXT" \
  '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $context
    }
  }'

exit 0
