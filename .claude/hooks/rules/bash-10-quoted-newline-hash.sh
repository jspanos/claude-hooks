# =============================================================================
# bash-10-quoted-newline-hash.sh — Rule: multi-line markdown in quoted args
#
# Claude Code's own command parser forces a permission prompt — overriding any
# allow rule — when a quoted argument contains a newline followed by '#':
#
#   "Newline followed by # inside a quoted argument can hide arguments from
#    path validation"
#
# The usual culprit is an inline PR/issue/commit body with markdown headings
# (`gh pr create --body "## Summary ..."`). Denying here, with a pointer to
# --body-file / -F, lets the agent fix the call itself instead of stalling on
# a prompt the user has to click through.
# =============================================================================

# True if any single- or double-quoted string in the command contains a
# newline followed (after optional blanks) by '#'. Unquoted '# comment' lines
# are real shell comments and are skipped without toggling quote state.
_bash10_quoted_newline_hash() {
  printf '%s' "$1" | perl -e '
    local $/; my $s = <STDIN>; my $q = ""; my $n = length $s;
    my ($sq, $dq) = (chr 39, chr 34);
    for (my $i = 0; $i < $n; $i++) {
      my $c = substr($s, $i, 1);
      if ($q eq $sq) {
        if ($c eq $sq) { $q = ""; next }
      } elsif ($q eq $dq) {
        if ($c eq "\\") { $i++; next }
        if ($c eq $dq) { $q = ""; next }
      } else {
        if ($c eq "\\") { $i++; next }
        if ($c eq $sq || $c eq $dq) { $q = $c; next }
        if ($c eq "#" && ($i == 0 || substr($s, $i - 1, 1) =~ /\s/)) {
          my $j = index($s, "\n", $i); last if $j < 0; $i = $j;
        }
        next;
      }
      exit 0 if $c eq "\n" && substr($s, $i + 1) =~ /\A[ \t]*#/;
    }
    exit 1;
  '
}

bash_check_quoted_newline_hash() {
  local cmd="$1"

  _bash10_quoted_newline_hash "$cmd" || return 0

  local fix
  if printf '%s' "$cmd" | grep -qE '\bgh[[:space:]]+(pr|issue|release)\b'; then
    fix="Write the body to a file in your scratchpad with the Write tool, then pass it with --body-file <file> (gh release: --notes-file <file>)."
  elif printf '%s' "$cmd" | grep -qE '\bgit\b.*\b(commit|tag)\b'; then
    fix="Write the message to a file in your scratchpad with the Write tool, then pass it with -F <file>."
  else
    fix="Write the multi-line text to a file in your scratchpad with the Write tool and pass the file path instead."
  fi

  deny_and_log "bash-10" \
    "A quoted argument contains a newline followed by '#' (e.g. a markdown '## Heading'). Claude Code forces a permission prompt for this pattern regardless of allow rules. $fix"
}
