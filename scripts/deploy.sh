#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy claude-hooks globally or into a specific project
#
# Global (default): copies hooks to ~/.claude/hooks/ — applies to every project
# Local (--local):  copies hooks into <project>/.claude/hooks/ and wires up
#                   .claude/settings.json — applies to that project only
#
# Usage:
#   ./scripts/deploy.sh [options]
#
# Options:
#   -h, --help          Show this help message
#   -n, --dry-run       Show what would be copied without doing it
#   -f, --force         Skip the test gate and deploy anyway
#   --no-claude-md      Skip updating ~/.claude/CLAUDE.md (global mode only)
#   --local [path]      Install into <path>/.claude/hooks/ instead of globally
#                       Defaults to the current directory if no path is given.
#                       Also writes/merges .claude/settings.json in the target.
#
# Examples:
#   ./scripts/deploy.sh                        # global deploy
#   ./scripts/deploy.sh --dry-run              # preview global deploy
#   ./scripts/deploy.sh --force                # skip tests, global deploy
#   ./scripts/deploy.sh --local                # local deploy to current dir
#   ./scripts/deploy.sh --local ~/projects/foo # local deploy to specific path
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
UPDATE_CLAUDE_MD=true
LOCAL_MODE=false
LOCAL_TARGET=""

usage() {
  sed -n '/^# Usage:/,/^# ====/p' "$0" | grep '^#' | sed 's/^# \{0,2\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)      usage ;;
    -n|--dry-run)   DRY_RUN=true; shift ;;
    -f|--force)     FORCE=true; shift ;;
    --no-claude-md) UPDATE_CLAUDE_MD=false; shift ;;
    --local)
      LOCAL_MODE=true
      shift
      # Optional path argument: consume if next arg doesn't start with '-'
      if [[ $# -gt 0 && "$1" != -* ]]; then
        LOCAL_TARGET="$1"; shift
      fi
      ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ── Resolve destination ────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }

if $LOCAL_MODE; then
  TARGET_PROJECT="${LOCAL_TARGET:-$PWD}"
  TARGET_PROJECT="$(cd "$TARGET_PROJECT" && pwd)"  # normalize
  DEST="$TARGET_PROJECT/.claude/hooks"
  UPDATE_CLAUDE_MD=false   # not applicable for local installs
else
  TARGET_PROJECT=""
  DEST="$HOME/.claude/hooks"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

copy_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if $DRY_RUN; then
    local rel_src="${src#$PROJECT_DIR/}"
    if $LOCAL_MODE; then
      local rel_dst="${dst#$TARGET_PROJECT/}"
      printf "  [dry-run] cp %s → %s\n" "$rel_src" "$rel_dst"
    else
      local rel_dst="${dst#$HOME/}"
      printf "  [dry-run] cp %s → ~/%s\n" "$rel_src" "$rel_dst"
    fi
  else
    cp "$src" "$dst"
    chmod +x "$dst"
    log "${src#$PROJECT_DIR/}"
  fi
}

# ── Step 1: Run tests (unless --force) ───────────────────────────────────────

if ! $FORCE; then
  echo ""
  echo "Running tests..."
  if ! bash "$PROJECT_DIR/tests/run-tests.sh" 2>&1; then
    echo ""
    err "Tests failed — aborting deploy. Use --force to skip."
    exit 1
  fi
fi

# ── Step 2: Copy hook files ───────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
  echo "Dry run — files that would be deployed:"
elif $LOCAL_MODE; then
  echo "Deploying hooks to $TARGET_PROJECT/.claude/hooks/ ..."
else
  echo "Deploying hooks to ~/.claude/hooks/ ..."
fi
echo ""

# Core dispatcher and permission handler
copy_file "$PROJECT_DIR/.claude/hooks/pre-tool-use.sh"       "$DEST/pre-tool-use.sh"
copy_file "$PROJECT_DIR/.claude/hooks/permission-request.sh" "$DEST/permission-request.sh"

# Shared library
copy_file "$PROJECT_DIR/.claude/hooks/lib/common.sh"         "$DEST/lib/common.sh"

# Rules (all files in rules/ — sorted, so numbering determines load order)
for rule in "$PROJECT_DIR/.claude/hooks/rules/"*.sh; do
  copy_file "$rule" "$DEST/rules/$(basename "$rule")"
done

# Audit logger
copy_file "$PROJECT_DIR/.claude/hooks/audit/post-tool-audit.sh" "$DEST/audit/post-tool-audit.sh"

# Context injection
copy_file "$PROJECT_DIR/.claude/hooks/context/session-start-inject.sh" "$DEST/context/session-start-inject.sh"
copy_file "$PROJECT_DIR/.claude/hooks/context/prompt-inject.sh"        "$DEST/context/prompt-inject.sh"

# ── Step 3a: Update ~/.claude/CLAUDE.md (global mode) ────────────────────────

if $UPDATE_CLAUDE_MD; then
  CLAUDE_MD_SRC="$PROJECT_DIR/.claude/CLAUDE.md"
  CLAUDE_MD_DST="$HOME/.claude/CLAUDE.md"

  if [[ ! -f "$CLAUDE_MD_SRC" ]]; then
    warn "No .claude/CLAUDE.md found — skipping global CLAUDE.md update"
  elif $DRY_RUN; then
    printf "  [dry-run] cp .claude/CLAUDE.md → ~/.claude/CLAUDE.md\n"
  else
    cp "$CLAUDE_MD_SRC" "$CLAUDE_MD_DST"
    log ".claude/CLAUDE.md → ~/.claude/CLAUDE.md"
  fi
fi

# ── Step 3b: Write/merge .claude/settings.json (local mode) ──────────────────

if $LOCAL_MODE; then
  SETTINGS_SRC="$PROJECT_DIR/.claude/settings.json"
  SETTINGS_DST="$TARGET_PROJECT/.claude/settings.json"

  if [[ ! -f "$SETTINGS_SRC" ]]; then
    warn "No .claude/settings.json found in source — skipping settings update"
  elif $DRY_RUN; then
    if [[ -f "$SETTINGS_DST" ]]; then
      printf "  [dry-run] merge hooks → .claude/settings.json (existing file)\n"
    else
      printf "  [dry-run] cp .claude/settings.json → .claude/settings.json (new file)\n"
    fi
  else
    mkdir -p "$TARGET_PROJECT/.claude"
    if [[ ! -f "$SETTINGS_DST" ]]; then
      # No existing settings — copy directly
      cp "$SETTINGS_SRC" "$SETTINGS_DST"
      log ".claude/settings.json (created)"
    else
      # Existing settings — merge hooks key using jq
      if ! command -v jq &>/dev/null; then
        warn "jq not found — cannot merge settings.json. Install jq or copy manually."
        warn "Source: $SETTINGS_SRC"
      else
        local_hooks="$(jq '.hooks' "$SETTINGS_SRC")"
        merged="$(jq --argjson hooks "$local_hooks" \
          'if .hooks then .hooks = (.hooks * $hooks) else .hooks = $hooks end' \
          "$SETTINGS_DST")"
        echo "$merged" > "$SETTINGS_DST"
        log ".claude/settings.json (hooks merged)"
      fi
    fi
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
  echo "Dry run complete. Run without --dry-run to apply."
elif $LOCAL_MODE; then
  printf "${GREEN}Deploy complete.${NC} Hooks are active in: $TARGET_PROJECT\n"
else
  printf "${GREEN}Deploy complete.${NC} Hooks are active in all Claude Code projects.\n"
fi
echo ""
