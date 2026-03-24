# Project: Claude Hooks

Safety guards, audit logging, and context injection for Claude Code — deployable globally.

## Architecture

```
.claude/hooks/
  lib/common.sh              # shared utilities (sourced by all hooks)
  rules/                     # one file per rule, sourced by pre-tool-use.sh
    bash-1-absolute-paths.sh
    bash-2-uncommitted-files.sh
    bash-3-remote-readonly.sh
    bash-4-inline-scripts.sh
    bash-5-pipe-abuse.sh
    bash-6-python-venv.sh
    file-1-sensitive-paths.sh
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
| `PreToolUse` | `pre-tool-use.sh` | Log + apply all 7 safety rules |
| `PostToolUse` | `audit/post-tool-audit.sh` | JSONL outcome log (async) |
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
| `file-1` | Write/Edit | Writes to `.env`, `*.pem`, `.ssh/`, kubeconfig, credentials |

## Testing

```bash
./tests/run-tests.sh               # run all 74 tests
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
