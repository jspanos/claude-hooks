#!/usr/bin/env bash
# =============================================================================
# git-push.test.sh — Tests for git_push_needs_review (lib/git-push.sh), which
# decides whether permission-request.sh defers a `git push` to the user.
# "blocked" below means "deferred for review"; "allowed" means auto-approved.
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/lib" && pwd)"

source "$TESTS_DIR/lib/assert.sh"
source "$LIB_DIR/git-push.sh"

# ── Fixture: repo on feature branch, origin default branch "trunk-ish" ──────
REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" branch feature
git -C "$REPO" tag v1.0
git -C "$REPO" update-ref refs/remotes/origin/trunk-ish HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk-ish
git -C "$REPO" checkout -q feature

check() {
  _reset
  git_push_needs_review "$1" "${2:-$REPO}" && _BLOCKED="true" _BLOCK_RULE="defer"
}

# =============================================================================

echo "git-push: permission-request push classification"

suite "Routine pushes — auto-allowed"

check "git push -q -u origin test/chart-version-current 2>&1 | tail -1"
assert_allowed "push -u origin feature-branch | tail"

check "git push"
assert_allowed "argument-less push from feature branch"

check "git push origin HEAD"
assert_allowed "push origin HEAD (on feature)"

check "git push origin feature:feature"
assert_allowed "explicit src:dst feature refspec"

check "git push --dry-run origin main"
assert_allowed "dry-run to main"

check "git push -n --force origin main"
assert_allowed "-n wins over --force"

check "git status && git log --oneline -3"
assert_allowed "no push at all"

check "git -C . push origin feature"
assert_allowed "git -C . push feature"

suite "Risky pushes — deferred"

check "git push --force origin feature"
assert_blocked "--force"

check "git push --force-with-lease origin feature"
assert_blocked "--force-with-lease"

check "git push -fu origin feature"
assert_blocked "short cluster -fu"

check "git push origin +feature"
assert_blocked "+refspec force"

check "git push origin main"
assert_blocked "push main"

check "git push origin feature:master"
assert_blocked "feature:master"

check "git push origin HEAD:refs/heads/release/2.0"
assert_blocked "HEAD:refs/heads/release/2.0"

check "git push origin trunk-ish"
assert_blocked "remote default branch (origin/HEAD)"

check "git push origin :feature"
assert_blocked ":ref deletion"

check "git push --delete origin feature"
assert_blocked "--delete"

check "git push --tags"
assert_blocked "--tags"

check "git push origin v1.0"
assert_blocked "bare name that is a local tag"

check "git push origin refs/tags/v2"
assert_blocked "refs/tags/*"

check "git push --mirror backup"
assert_blocked "--mirror"

check "git fetch && git push origin main"
assert_blocked "push main after &&"

check "git checkout main && git push"
assert_blocked "implicit push after checkout in same command"

check "git switch -c topic && git push -u origin topic"
assert_allowed "explicit feature push after switch"
check "git push" "/nonexistent-dir-for-test"
assert_blocked "implicit push where branch can't be resolved"

suite "Unparseable pushes — fail closed"

check "git push origin \$BRANCH"
assert_blocked "variable expansion in refspec"

check "git push origin \$(git rev-parse --abbrev-ref HEAD)"
assert_blocked "command substitution"

check "env GIT_DIR=x git push origin feature"
assert_blocked "env wrapper"

check "command git push origin feature"
assert_blocked "command wrapper"

check "echo origin | xargs git push"
assert_blocked "xargs wrapper"

check "bash -c 'git push origin main'"
assert_blocked "bash -c wrapper"

check "(cd sub && git push origin feature)"
assert_blocked "subshell"

check "git -c remote.origin.push=refs/heads/*:refs/heads/main push"
assert_blocked "git -c override"

check "git -c alias.p=push p origin main"
assert_blocked "-c alias to push"

check "git status & git push origin main"
assert_blocked "push after single & is still parsed"

check "git push 2>&1 origin main"
assert_blocked "redirect before refspec does not hide main"

git -C "$REPO" config alias.p push
check "git p origin main"
assert_blocked "configured alias expanding to push"

git -C "$REPO" config alias.sh '!f() { git push origin main; }; f'
check "git sh"
assert_blocked "shell alias"

git -C "$REPO" config remote.origin.push 'refs/heads/*:refs/heads/main'
check "git push"
assert_blocked "remote.origin.push config redirects implicit push"
git -C "$REPO" config --unset remote.origin.push

check "git push -q -u origin feature 2>&1 | tail -1; gh pr create --title \"test(chart): x\" --body-file b.md | tail -1"
assert_allowed "screenshot flow with body-file still auto-allowed"

summary
