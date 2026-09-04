# Project: Claude Hooks

Safety guards, audit logging, and context injection for Claude Code — deployable globally.

## Architecture

```
.claude-hooks-source         # marker: this repo may edit its own hooks
.claude/hooks/
  lib/common.sh              # shared utilities (sourced by all hooks)
  lib/protected-paths.sh     # matcher for hook-infrastructure paths (bash-7, file-2)
  lib/mutation-targets.sh    # "what does this command destroy?" (bash-2, bash-7)
  rules/                     # one file per rule, sourced by pre-tool-use.sh
    bash-1-absolute-paths.sh
    bash-2-uncommitted-files.sh
    bash-3-remote-readonly.sh
    bash-4-inline-scripts.sh
    bash-5-pipe-abuse.sh
    bash-6-python-venv.sh
    bash-7-protected-config.sh
    bash-8-interpreter-file-ops.sh
    bash-9-blocking-waits.sh
    file-1-sensitive-paths.sh
    file-2-protected-config.sh
  pre-tool-use.sh            # PreToolUse dispatcher: logs + runs all rules
  permission-request.sh      # PermissionRequest: auto-allow/deny/defer
  audit/
    post-tool-audit.sh       # PostToolUse: JSONL outcome log (async)
  context/
    session-start-inject.sh  # SessionStart: inject project-context.md
    prompt-inject.sh         # UserPromptSubmit: keyword-triggered injection
  CLAUDE.md                  # global agent instructions (deployed to ~/.claude/)
tests/
  lib/assert.sh              # test harness (mocks deny_and_log)
  rules/                     # *.test.sh per rule
  run-tests.sh               # aggregated test runner
scripts/
  deploy.sh                  # deploy hooks to ~/.claude/hooks/
  SCRIPTS.md                 # script registry
context/
  project-context.md         # this file; injected on session start
```

## Setup

Requirements: `jq` (`brew install jq`), `perl` (pre-installed on macOS)

Deploy globally:
```bash
./scripts/deploy.sh
```

## Hook Configuration

Wired in `.claude/settings.json`:

| Event | Script | Purpose |
|---|---|---|
| `PermissionRequest` | `permission-request.sh` | Auto-allow safe ops, auto-deny dangerous, defer external state changes |
| `PreToolUse` | `pre-tool-use.sh` | Log + apply all 11 rules; may rewrite the Bash `timeout` |
| `PostToolUse` | `audit/post-tool-audit.sh` | JSONL outcome log with `duration_ms` (async) |
| `SessionStart` | `context/session-start-inject.sh` | Re-inject project context |
| `UserPromptSubmit` | `context/prompt-inject.sh` | Keyword-triggered section injection |

## Safety Rules

| Rule | Trigger | What it blocks |
|---|---|---|
| `bash-1` | Bash | Absolute paths inside `$PROJECT_DIR` or `$HOME` |
| `bash-2` | Bash | Deletion/overwrite of files with uncommitted git changes |
| `bash-3` | Bash | Modifying kubectl subcommands; system-modifying SSH remote commands |
| `bash-4` | Bash | Inline scripts (heredocs, `bash -c` chains, echo shebang) |
| `bash-5` | Bash | Pipe abuse: `curl\|bash`, `xargs rm`, `find -delete`, pipe to sudo |
| `bash-6` | Bash | Bare `python`, pip install, python3 without venv |
| `bash-7` | Bash | Deleting/overwriting/chmod-ing `.claude/hooks/`, `settings*.json` |
| `bash-8` | Bash | Inline `python -c` / `node -e` code that mutates files or shells out |
| `bash-9` | Bash | Foreground waits on external state (CI watching, cluster/cloud waiters, `tail -f`, dev servers, `sleep` > 5s, `until`/`while` poll loops); also sets and clamps the Bash `timeout` |
| `file-1` | Write/Edit | Writes to `.env`, `*.pem`, `.ssh/`, kubeconfig, credentials |
| `file-2` | Write/Edit + any path-taking tool | Writes to hook enforcement files |

`bash-2` and `bash-7` share `lib/mutation-targets.sh`, which walks a command
segment by segment (tracking `cd`) and models: `rm`, `unlink`, `shred`, `mv`,
`cp`, `install`, `ln -f`, `rsync`, `scp`, `truncate`, `ed`, `ex`, `sed -i`,
`dd of=`, `tee`, `>` redirects, `chmod`/`chown`, `patch`, and
`git checkout`/`restore`/`clean -f`/`reset --hard`.

### Tool coverage

`pre-tool-use.sh` applies file rules to `Write`, `Edit`, `NotebookEdit`, **and**
any other tool (including MCP servers) that names a path *and* either carries a
content-ish payload or has a write-ish name. Read-only tools match neither test
and are untouched.

### Protecting the hooks from themselves

`bash-7` and `file-2` refuse to modify the enforcement layer, because an agent
that can rewrite one rule file can disable all the others. The exemption is a
`.claude-hooks-source` file at the repo root — and that marker is itself a
protected path, so an agent cannot create it to self-authorise. Bootstrapping a
new hooks-source checkout therefore requires a human to create the marker.

### Wall-clock rules (bash-9)

`bash-9` is the only rule aimed at wasted time rather than safety. It was
derived from the audit log itself: over ~19k paired Bash calls, 29% of all Bash
wall time went to `sleep` and `until`-poll loops, and ~170 calls hit the 600s
ceiling and were killed — nearly all of them CI watchers. Only 1.3% of calls
used `run_in_background`.

Two halves:

- **Deny foreground waits on external state** — the agent should background
  them (`run_in_background: true`) or arm a `Monitor`, then keep working.
- **Set the `timeout` for slow real work** via `hookSpecificOutput.updatedInput`
  (tests 300s, browser/e2e 480s, builds and installs 600s) when the call gives
  none, and clamp anything over the 600000ms ceiling. No `permissionDecision`
  is emitted, so the normal permission flow still applies.

`PostToolUse` records now carry `ts_ms` and `duration_ms`, so "what is slow"
is a single `jq` over `audit.jsonl` instead of a Pre/Post join on ISO stamps
that only had second resolution.

Known false positive: the rule matches command *text*, so a shell command that
merely mentions a blocked pattern (`perl -pi -e` rewriting docs that name
`gh run watch`) is denied. Edit docs with the Edit/Write tools, which is the
house rule anyway.

### Known limitations — do not oversell these rules

These are guardrails against accidents, not a security boundary:

- **Interpreters are Turing-complete.** `bash-8` matches obvious API calls;
  obfuscation (`getattr(os,'rem'+'ove')`, base64, `importlib`) defeats any
  pattern match. Real containment needs OS-level sandboxing.
- **Script contents are never inspected.** `Write scripts/x.py` then
  `uv run python3 scripts/x.py` passes every rule. This is structural — the
  `scripts/` workflow `bash-4` recommends is itself unchecked.
- **Compiled/aliased escapes are unmodelled** — `make`, `npm run`, a shell
  function, or any binary that writes files.

## Testing

```bash
./tests/run-tests.sh               # run all rule tests
bash tests/rules/bash-3.test.sh    # run a single rule
```

## Deployment

```bash
./scripts/deploy.sh            # test + deploy to ~/.claude/hooks/
./scripts/deploy.sh --dry-run  # preview without writing
./scripts/deploy.sh --force    # deploy without running tests
```

## API

Hook script communication protocol:
- **stdin** — JSON payload from Claude Code
- **stdout** — JSON response (decisions/context)
- **stderr** — Error messages
- **exit 0** — Success; Claude processes stdout JSON if present
- **exit 2** — Block action; stderr message shown to Claude

## Configuration

To add a new rule:
1. Create `.claude/hooks/rules/bash-N-description.sh` with one function
2. Add `bash_check_<name>()` call to the `Bash)` block in `pre-tool-use.sh`
3. Add a test file at `tests/rules/bash-N.test.sh`
4. Run `./tests/run-tests.sh` to verify
5. Run `./scripts/deploy.sh` to apply globally

Shared helpers go in `.claude/hooks/lib/` and must be sourced from
`pre-tool-use.sh`. `deploy.sh` copies `lib/*.sh` and `rules/*.sh` by glob, so
new files there deploy automatically. A test that exercises a rule depending on
a lib must source that lib itself — but always **after** `tests/lib/assert.sh`,
so the `deny_and_log` mock stays installed.
