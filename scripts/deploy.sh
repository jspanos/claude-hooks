#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Deploy claude-hooks to ~/.claude/hooks/
#
# Copies all hook scripts from this project to the global Claude Code hooks
# directory so they apply to every project on this machine.
#
# Usage:
#   ./scripts/deploy.sh [options]
#
# Options:
#   -h, --help        Show this help message
#   -n, --dry-run     Show what would be copied without doing it
#   -f, --force       Skip the test gate and deploy anyway
#   --no-claude-md    Skip updating ~/.claude/CLAUDE.md
#
# Examples:
#   ./scripts/deploy.sh               # run tests, then deploy
#   ./scripts/deploy.sh --dry-run     # preview changes
#   ./scripts/deploy.sh --force       # deploy without running tests
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
UPDATE_CLAUDE_MD=true

usage() {
  sed -n '/^# Usage:/,/^# ====/p' "$0" | grep '^#' | sed 's/^# \{0,2\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)         usage ;;
    -n|--dry-run)      DRY_RUN=true; shift ;;
    -f|--force)        FORCE=true; shift ;;
    --no-claude-md)    UPDATE_CLAUDE_MD=false; shift ;;
    *)                 echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

DEST="$HOME/.claude/hooks"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }

copy_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if $DRY_RUN; then
    local rel_src="${src#$PROJECT_DIR/}"
    local rel_dst="${dst#$HOME/}"
    printf "  [dry-run] cp %s → ~/%s\n" "$rel_src" "$rel_dst"
  else
    cp "$src" "$dst"
    chmod +x "$dst"
    local rel="${src#$PROJECT_DIR/}"
    log "$rel"
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
copy_file "$PROJECT_DIR/.claude/hooks/audit/post-tool-audit.sh"   "$DEST/audit/post-tool-audit.sh"

# Context injection
copy_file "$PROJECT_DIR/.claude/hooks/context/session-start-inject.sh" "$DEST/context/session-start-inject.sh"
copy_file "$PROJECT_DIR/.claude/hooks/context/prompt-inject.sh"         "$DEST/context/prompt-inject.sh"

# ── Step 3: Update ~/.claude/CLAUDE.md ───────────────────────────────────────

if $UPDATE_CLAUDE_MD; then
  CLAUDE_MD_SRC="$PROJECT_DIR/.claude/CLAUDE.md"
  CLAUDE_MD_DST="$HOME/.claude/CLAUDE.md"

  if [[ ! -f "$CLAUDE_MD_SRC" ]]; then
    warn "No .claude/CLAUDE.md found in project — skipping global CLAUDE.md update"
  elif $DRY_RUN; then
    printf "  [dry-run] cp .claude/CLAUDE.md → ~/.claude/CLAUDE.md\n"
  else
    cp "$CLAUDE_MD_SRC" "$CLAUDE_MD_DST"
    log ".claude/CLAUDE.md → ~/.claude/CLAUDE.md"
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
  echo "Dry run complete. Run without --dry-run to apply."
else
  printf "${GREEN}Deploy complete.${NC} Hooks are active in all Claude Code projects.\n"
fi
echo ""
