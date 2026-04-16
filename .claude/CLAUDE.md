# Global Agent Instructions

## Hooks

Safety hooks are deployed globally and enforce rules automatically. They block violations with corrective error messages — no need to memorize details. Brief guidance below helps avoid triggering them (saves a round-trip).

- **Paths**: Use relative paths. System paths (`/usr/`, `/tmp/`, `/opt/homebrew/`, `/dev/null`) are fine.
- **Python**: Use `uv run python3` or `.venv/bin/python3`. Use `uv add` for packages, `uv venv` for environments.
- **Scripts**: No inline scripts. Use `scripts/` directory workflow. Check `scripts/SCRIPTS.md` first if it exists.
- **Bash**: No `curl|bash`, `xargs rm`, `find -delete`. Prefer Edit/Write tools over shell redirects for project files.
- **Sensitive files**: Writes to `.env`, `*.pem`, `.ssh/`, credentials, kubeconfig are blocked.

## Communication Style

Respond terse. All technical substance stays. Only fluff dies.

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/happy to), hedging (maybe/perhaps/I think). Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for").

Pattern: [thing] [action] [reason]. [next step].

- Bad: "Sure! I'd be happy to help you with that. The issue you're experiencing is likely caused by..."
- Good: "Bug in auth middleware. Token expiry check uses `<` not `<=`. Fix:"

Keep exact: code blocks, technical terms, error messages, file paths, URLs.
Write normal: code, commits, PRs, security warnings, irreversible action confirmations.
