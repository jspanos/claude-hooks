# Claude Code Hooks

Safety guards, audit logging, and context injection for Claude Code — deployable globally across all your projects.

## What This Is

Claude Code is powerful, but that power cuts both ways. This project wraps it with a set of hooks that:

- **Block dangerous command patterns** before they execute
- **Auto-approve safe operations** and defer irreversible external changes
- **Log every tool call** to a local audit trail
- **Inject project context** automatically on session start and based on what you're asking about

Everything deploys to `~/.claude/hooks/` and applies globally — once installed, it runs in every project.

## Quickstart

```bash
# Install dependencies (macOS)
brew install jq

# Deploy globally
./scripts/deploy.sh
```

That's it. All 7 safety rules are now active in every Claude Code session.

---

## Safety Rules

Rules fire on every `Bash`, `Write`, or `Edit` call before execution. If a rule triggers, the action is blocked and Claude is told why.

### bash-1 — Absolute Project/Home Paths

Blocks absolute paths inside your project or home directory and suggests relative equivalents. Absolute paths are unnecessary and trigger extra permission prompts.

| Allowed | Blocked |
|---|---|
| `./src/index.ts` | `/Users/yourname/project/src/index.ts` |
| `/usr/bin/env` | `/Users/yourname/scripts/run.sh` |
| `/tmp/scratch.txt` | `/home/yourname/configs/settings.json` |

System paths (`/usr/`, `/opt/homebrew/`, `/tmp/`, `/dev/`, etc.) are always allowed.

---

### bash-2 — Uncommitted File Protection

Blocks destructive operations (`rm`, `sed -i`, `>` redirect, `mv`, `tee`, `truncate`, `dd`) on files with uncommitted git changes. Prevents data loss before you've had a chance to commit.

```
# Blocked — file has unstaged modifications
rm config.json

# Blocked — untracked file would be lost
sed -i 's/old/new/' notes.txt

# Blocked — staged file would be overwritten
echo "new content" > draft.md
```

Globs and variables are skipped (can't resolve them safely). Files outside the project are not checked.

---

### bash-3 — Remote Read-Only

Enforces read-only access for `kubectl` and SSH.

**kubectl:** Allows `get`, `describe`, `logs`, `explain`, `diff`, and other read-only subcommands. Blocks `apply`, `delete`, `edit`, `patch`, `exec`, `scale`, and anything else that modifies cluster state.

**SSH:** Interactive sessions (`ssh user@host`) are allowed. Remote commands that modify the system are blocked — including `rm`, `apt-get install`, `systemctl restart`, `chmod`, `kill`, `wget`, `tee`, output redirects, and more.

---

### bash-4 — No Inline Scripts

Blocks creation of scripts via shell one-liners. Forces use of the `scripts/` directory, which keeps automation reviewable and versioned.

**Blocked patterns:**
- Heredoc writes: `cat > file.sh << EOF`
- Echo shebang: `echo '#!/bin/bash' > script.sh`
- Long `bash -c` chains (4+ command separators)
- Long inline `-e` / `-c` expressions for python/node/ruby (>150 chars)

If a `scripts/SCRIPTS.md` exists, the block message tells you to check it first — a script may already exist.

---

### bash-5 — Pipe Abuse

Blocks dangerous data-flow patterns:

| Pattern | Risk |
|---|---|
| `curl ... \| bash` | Remote code execution |
| `base64 -d ... \| bash` | Obfuscated execution |
| `cmd \| eval` | Code injection |
| `$(curl ...)` | Command substitution RCE |
| `find ... -delete` | Recursive deletion |
| `... \| xargs rm` | Bulk deletion via pipe |
| `cmd \| sudo` | Privilege escalation via pipe |
| Write-then-execute same command | Script review bypass |
| Writes to `/etc/`, `/usr/bin/`, etc. | System path modification |

---

### bash-6 — Python Virtual Environment

Enforces Python hygiene: no bare `python`, no global `pip install`, no running scripts outside a venv. Prefers `uv` when available.

| Command | Behavior |
|---|---|
| `python script.py` | Blocked — use `python3` |
| `pip install requests` | Blocked — use `uv add requests` |
| `python3 -m pip install x` | Blocked — use `uv add x` |
| `python3 -m venv .venv` (with uv) | Blocked — use `uv venv` |
| `python3 script.py` (no `.venv`) | Blocked — create venv first |
| `uv run python3 script.py` | Allowed |
| `.venv/bin/python3 script.py` | Allowed |

---

### file-1 — Sensitive File Writes

Blocks `Write` and `Edit` calls to files that likely contain secrets:

- `.env`, `.env.local`, `.env.production`, etc.
- `*.pem`, `*.key`, `*.p12`, `*.crt`, `*.cer`
- `.ssh/` directory
- `credentials.json`, `secrets.yaml`, `tokens.toml`, etc.
- `~/.aws/credentials`, `~/.gcp/key`, `~/.azure/config`
- `.kube/config`, `.docker/config.json`
- `terraform.tfstate`, `terraform.tfstate.backup`
- `*.gpg`, `*.pgp`, `*.keychain`, `*.kdbx`
- `.netrc`, `.npmrc`, `.pypirc`, `.gitcredentials`

---

## Permission System

Separate from the safety rules, the `PermissionRequest` hook handles Claude Code's permission prompts automatically:

| Situation | Decision | Reason |
|---|---|---|
| Read-only tools (Glob, Grep, Read…) | Allow | No side effects |
| Web tools (WebFetch, WebSearch) | Allow | Pre-tool rules guard real dangers |
| Project-local writes | Allow | Pre-tool rules apply |
| Dangerous pattern (rm -rf, curl\|bash…) | Deny | Hard block |
| Writes to sensitive paths | Deny | Hard block |
| Writes outside project | Defer | Unusual; ask user |
| External publishing (git push, npm publish, terraform apply…) | Defer | Irreversible; ask user |

"Defer" means Claude Code shows you a confirmation dialog before proceeding.

---

## Audit Log

Every tool call is logged to `.claude/logs/audit.jsonl` — one JSON record per line. The file is excluded from git via `.gitignore`.

**PreToolUse record:**
```json
{
  "timestamp": "2026-03-24T15:30:45Z",
  "session_id": "s-123",
  "event": "PreToolUse",
  "tool_name": "Bash",
  "tool_use_id": "t-456",
  "cwd": "./my-project",
  "tool_input": { "command": "ls -la" },
  "blocked": false
}
```

When a rule blocks, `"blocked": true` plus `"rule"` and `"reason"` are added.

**PostToolUse record** (async, never blocks Claude):
```json
{
  "timestamp": "2026-03-24T15:30:45Z",
  "event": "PostToolUse",
  "tool_name": "Bash",
  "success": true,
  "tool_input": { "command": "ls -la" },
  "tool_response": { "output": "..." }
}
```

---

## Context Injection

Two hooks keep Claude aware of your project without you having to repeat yourself.

**SessionStart** — On every new session, resume, or context compaction, `context/project-context.md` is injected in full.

**UserPromptSubmit** — When you mention relevant keywords, only the matching sections of `project-context.md` are injected:

| Keywords in your message | Section injected |
|---|---|
| deploy, release, production | `## Deployment` |
| architect, structure, overview | `## Architecture` |
| test, spec, coverage | `## Testing` |
| install, setup, run locally | `## Setup` |
| api, endpoint, route | `## API` |
| database, schema, migration | `## Database` |
| env, config, settings | `## Configuration` |
| hook, audit, safety guard | `## Hook Configuration` |

Edit `context/project-context.md` and the keyword-to-section mapping in `.claude/hooks/context/prompt-inject.sh` to match your project.

---

## Expanding the System

### Adding a New Bash Rule

1. Create `.claude/hooks/rules/bash-7-your-rule.sh`:

```bash
#!/usr/bin/env bash
# bash-7: description of what this blocks

bash_check_your_rule() {
  local command="$1"

  # Your detection logic here
  if echo "$command" | grep -qE 'some_pattern'; then
    deny_and_log "bash-7" "Reason shown to Claude"
  fi
}
```

2. Register it in `.claude/hooks/pre-tool-use.sh` inside the `Bash)` block:

```bash
bash_check_your_rule "$COMMAND"
```

3. Write a test file at `tests/rules/bash-7.test.sh`:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/assert.sh"
source "$SCRIPT_DIR/../../.claude/hooks/lib/common.sh"
source "$SCRIPT_DIR/../../.claude/hooks/rules/bash-7-your-rule.sh"

suite "bash-7: your rule description"

_BLOCKED=""; bash_check_your_rule "safe command"
assert_allowed "safe command is allowed"

_BLOCKED=""; bash_check_your_rule "some_pattern_here"
assert_blocked "dangerous pattern is blocked" "bash-7"

summary
```

4. Run tests and deploy:

```bash
./tests/run-tests.sh
./scripts/deploy.sh
```

---

### Adding a Write/Edit Rule

Rules for `Write` and `Edit` calls live in the same `rules/` directory. Register them in the `Write|Edit)` block of `pre-tool-use.sh`:

```bash
Write|Edit)
  FILE_PATH="$(get_field "$HOOK_INPUT" ".tool_input.file_path")"
  file_check_sensitive_paths "$FILE_PATH"
  file_check_your_new_rule   "$FILE_PATH"   # add here
  ;;
```

---

### Customizing the Permission Hook

`permission-request.sh` has three decision functions you can extend:

- `_bash_is_dangerous()` — add patterns that should always be hard-denied
- `_bash_is_external_publish()` — add commands that should be deferred (require user confirmation)
- `_is_sensitive_path()` — add file path patterns that should block Write/Edit

Each function contains a `DENY_PATTERNS` / `DEFER_PATTERNS` / `SENSITIVE` array — add your regex to the array.

---

### Customizing Context Injection

**Add a new keyword trigger** in `prompt-inject.sh`:

```bash
PATTERNS=(
  # ... existing patterns ...
  'your_keyword|another_keyword'     # add here
)
HEADERS=(
  # ... existing headers ...
  "## Your Section Header"           # matching index
)
```

Then add the corresponding section to `context/project-context.md`:

```markdown
## Your Section Header

Content that gets injected when the user mentions your keywords.
```

---

## Testing

```bash
./tests/run-tests.sh                    # run all tests
bash ./tests/rules/bash-1.test.sh       # run one rule's tests
```

The test harness (`tests/lib/assert.sh`) mocks `deny_and_log` and `deny_tool_use` so rules can be tested without side effects. Each rule file has its own test suite.

---

## Deployment

```bash
./scripts/deploy.sh               # run tests, then deploy to ~/.claude/hooks/
./scripts/deploy.sh --dry-run     # preview what would be copied
./scripts/deploy.sh --force       # skip tests (not recommended)
./scripts/deploy.sh --no-claude-md  # don't update ~/.claude/CLAUDE.md
```

Files are copied to `~/.claude/hooks/` and take effect immediately in new Claude Code sessions.

---

## Repository Layout

```
.claude/hooks/
  lib/common.sh              # shared utilities (jq helpers, audit logging, deny)
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
tests/
  lib/assert.sh              # test harness
  rules/                     # *.test.sh per rule
  run-tests.sh               # aggregated runner
scripts/
  deploy.sh                  # deploy to ~/.claude/hooks/
  SCRIPTS.md                 # script registry
context/
  project-context.md         # injected on session start and keyword match
```

## Requirements

- macOS or Linux
- `jq` — `brew install jq` / `apt install jq`
- `perl` — pre-installed on macOS
- Claude Code CLI
