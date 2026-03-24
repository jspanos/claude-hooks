# Global Agent Instructions

## Paths
- Use **relative paths** in bash commands. Avoid absolute paths within the project or home directory.
- System paths (`/usr/`, `/tmp/`, `/opt/homebrew/`, `/dev/null`) are always fine.

## Python
- Never use bare `python` — always `python3`
- All Python work must run inside a virtual environment (`.venv/`)
- Use `uv` for environment and package management:
  - Create venv: `uv venv`
  - Add packages: `uv add <package>` (not pip install)
  - Run scripts: `uv run python3 <script>`
- Only use `.venv/bin/python3` or `uv run python3` — never bare `python3` without a venv

## Scripts
- Never create inline scripts (no `bash -c 'a; b; c; d'`, no heredoc script files, no `echo '#!/bin/bash' > file.sh`)
- When automation is needed, create a proper script file with `--help` support
- Check if a `scripts/` directory exists in the project — if so, check `scripts/SCRIPTS.md` first

## Bash Safety
- Never pipe network content to an interpreter: no `curl | bash`, `wget | sh`
- Never use `xargs rm` or `find -delete` without a dry-run step first
- Prefer git-tracked edits (Edit/Write tools) over shell redirects for project files
