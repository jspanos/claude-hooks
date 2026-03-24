# =============================================================================
# bash-3-remote-readonly.sh — Rule: SSH and kubectl must be read-only
#
# Remote operations that modify systems or cluster state are not permitted.
# Interactive SSH (no remote command) is allowed.
# =============================================================================

bash_check_remote_readonly() {
  local cmd="$1"

  # ── kubectl ───────────────────────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*kubectl\b'; then
    # Extract first subcommand (skip flags like --context, --namespace)
    local subcmd
    subcmd="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*kubectl[[:space:]]+//' | \
              tr ' ' '\n' | grep -v '^-' | head -1)"

    case "$subcmd" in
      # ── Read-only: allow ─────────────────────────────────────────────────
      get|describe|logs|explain|version|cluster-info|top|diff|wait|\
      api-resources|api-versions|auth|config|completion|options|plugin|\
      certificate|kustomize)
        return 0
        ;;
      # ── Modifying: block ─────────────────────────────────────────────────
      apply|create|delete|edit|patch|replace|rollout|scale|set|label|\
      annotate|cordon|uncordon|drain|taint|exec|port-forward|run|expose|\
      autoscale|attach|cp|debug|replace|convert)
        deny_and_log "bash-3" \
          "kubectl '$subcmd' modifies cluster state. Only read-only kubectl commands are allowed (get, describe, logs, explain, top, etc.). Run cluster-modifying commands manually outside of Claude."
        ;;
      *)
        # Unknown subcommand — warn but allow
        printf '%s\n' "[claude-hooks] WARNING: unknown kubectl subcommand '$subcmd' — allowing" >&2
        ;;
    esac
  fi

  # ── ssh ──────────────────────────────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*ssh\b'; then
    # Strip the 'ssh' prefix
    local ssh_rest
    ssh_rest="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*ssh[[:space:]]+//')"

    # Parse SSH arguments to extract the remote command.
    # We use perl to walk tokens properly: skip flags (and their values for
    # value-taking flags like -i, -p, -l …), find the [user@]host token, then
    # return everything after it. This avoids sed corrupting the remote command
    # (e.g. stripping -g from apt-get because 'g' appears in the boolean-flag set).
    #
    # Flags that consume the next token as a value (single-char, separate arg):
    #   i p l o b c E F I J L m Q R S w W
    local remote_cmd
    remote_cmd="$(printf '%s' "$ssh_rest" | perl -e '
      my $input = do { local $/; <STDIN> };
      chomp $input;
      my @tokens = split /\s+/, $input;
      my %takes_val = map { $_ => 1 } split //, "iplobcEFIJLmQRSwW";
      my $i = 0;
      while ($i < scalar @tokens) {
        my $tok = $tokens[$i];
        if ($tok =~ /^-(.+)$/) {
          my $flags = $1;
          # Single-char value-taking flag with no attached value: skip next token
          $i += (length($flags) == 1 && exists $takes_val{$flags}) ? 2 : 1;
        } else {
          # First non-flag token is the [user@]host — return everything after it
          print join(" ", @tokens[$i+1 .. $#tokens]);
          exit;
        }
      }
      print "";
    ')"

    # Interactive SSH (no remote command) — allow
    [[ -z "$remote_cmd" ]] && return 0

    # Patterns for system-modifying remote operations
    local -a SSH_BLOCK
    SSH_BLOCK=(
      'rm\s'                                       # file deletion
      'mv\s'                                       # move
      '\bsed\s+-i'                                 # in-place sed
      '\bchmod\s'                                  # permission change
      '\bchown\s'                                  # ownership change
      '\bsystemctl\s+(start|stop|restart|enable|disable|reload|mask)\b'
      '\bservice\s+\S+\s+(start|stop|restart)\b'
      '\bkill\b|\bpkill\b|\bkillall\b'
      '\bapt(-get)?\s+(install|remove|purge|upgrade|autoremove)\b'
      '\byum\s+(install|remove|update|erase)\b'
      '\bdnf\s+(install|remove|update)\b'
      '\bnpm\s+(install|uninstall|ci)\b'
      '\bpip[23]?\s+(install|uninstall)\b'
      '\bdd\s'
      '\btruncate\s'
      '\btee\s'
      '[^>]>[^>]'                                  # output redirect
      '\bcrontab\s+-[ler]\b'
      '\bpasswd\b|\badduser\b|\buseradd\b|\buserdel\b'
      '\bcurl\s.*-[oO]\s'                          # curl saving to file
      '\bwget\s'                                   # wget (downloads/modifies)
      '\bmkdir\s|\btouch\s'                        # creating files/dirs remotely
    )

    for pat in "${SSH_BLOCK[@]}"; do
      if printf '%s' "$remote_cmd" | grep -qE "$pat"; then
        deny_and_log "bash-3" \
          "SSH command contains a system-modifying operation. Remote command: '$remote_cmd'. Only read-only SSH commands are allowed (ls, cat, grep, ps, df, etc.). Run system-modifying commands manually outside of Claude."
      fi
    done
  fi
}
