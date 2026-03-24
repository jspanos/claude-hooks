# Claude Code Hooks — Agent Instructions

This project manages Claude Code hooks: safety guards, audit logging, and context injection.

## Key Rules (Enforced by Hooks)

These rules are automatically enforced. Understanding them avoids wasted round-trips:

### Paths
- Use **relative paths** (e.g., `./src/file.ts`), not absolute paths like `/Users/yourname/...`
- Absolute system paths (`/usr/`, `/tmp/`, `/opt/homebrew/`) are fine

### Python
- Never use bare `python` — always `python3`
- All Python work must use a virtual environment (`.venv/`)
- Prefer `uv` for everything: `uv venv`, `uv add <pkg>`, `uv run python3 <script>`
- Never `pip install` — use `uv add <package>` instead
- Never `python -m venv` — use `uv venv` instead

### Scripts
- **Never create inline scripts** (heredocs, `bash -c` chains, `echo '#!/...' > file.sh`)
- Instead, use the `scripts/` directory workflow (see below)

### Bash
- No piping network content to interpreters: `curl | bash`, `wget | sh`
- No bulk deletion via pipes: `xargs rm`, `find -delete`
- Check git status before destructive operations on modified files

## Scripts Workflow

Before writing any script:

1. **Read `scripts/SCRIPTS.md`** — a similar script may exist; modify it instead of creating a new one
2. **Check with `--help`** — `./scripts/<name>.sh --help` shows all options
3. **If creating new:**
   - Use the Write tool: create `scripts/<descriptive-name>.sh` (or `.py`)
   - Bash: start with `#!/usr/bin/env bash` + `set -euo pipefail`
   - Python: start with `#!/usr/bin/env python3` + `argparse`
   - Add `--help` / `-h` that prints usage and examples
   - Make executable: `chmod +x scripts/<name>.sh`
   - **Add a row to `scripts/SCRIPTS.md`**: `| scripts/<name>.sh | description | --flags |`

## Running Tests

```bash
./tests/run-tests.sh        # run all hook rule tests
bash tests/rules/bash-1.test.sh   # run a single rule's tests
```

## Hook Architecture

```
.claude/hooks/
  lib/common.sh          # shared utilities
  rules/                 # one file per rule (bash-1 through bash-6, file-1)
  pre-tool-use.sh        # dispatcher: sources rules/, routes by tool
  permission-request.sh  # auto-allow/deny/defer permission prompts
  audit/                 # PostToolUse JSONL logging
  context/               # SessionStart + UserPromptSubmit injection
tests/
  lib/assert.sh          # test harness (mocks deny_and_log)
  rules/                 # *.test.sh per rule
  run-tests.sh           # test runner
```
