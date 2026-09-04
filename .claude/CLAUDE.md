# Global Agent Instructions

## Hooks

Safety hooks are deployed globally and enforce rules automatically. They block violations with corrective error messages — no need to memorize details. Brief guidance below helps avoid triggering them (saves a round-trip).

- **Paths**: Use relative paths. System paths (`/usr/`, `/tmp/`, `/opt/homebrew/`, `/dev/null`) are fine.
- **Python**: Use `uv run python3` or `.venv/bin/python3`. Use `uv add` for packages, `uv venv` for environments.
- **Scripts**: No inline scripts. Use `scripts/` directory workflow. Check `scripts/SCRIPTS.md` first if it exists.
- **Bash**: No `curl|bash`, `xargs rm`, `find -delete`. Prefer Edit/Write tools over shell redirects for project files. Destructive commands are caught behind `cd x &&` prefixes too, and include `cp`, `install`, `ln -f`, `patch`, `git checkout/restore`, `git clean -f`, `git reset --hard`.
- **Sensitive files**: Writes to `.env`, `*.pem`, `.ssh/`, credentials, kubeconfig are blocked.
- **Waiting**: Never block the foreground on external state. `gh run watch`, `gh pr checks --watch`, `kubectl wait`/`rollout status`, cloud `wait` subcommands, `tail -f`, dev servers, `sleep` over 5s, and `until/while … sleep` poll loops are blocked — run them with `run_in_background: true` (one notification on exit) or as a `Monitor` (one event per state change) and keep working meanwhile. Slow *work* is fine in the foreground: test suites, builds and installs get a timeout set automatically (tests 300s, browser tests 480s, builds/installs 600s); 600000ms is the tool ceiling and anything higher is clamped.
- **Interpreters**: Don't mutate files via `python3 -c` / `node -e` / `ruby -e` (`os.remove`, `shutil.rmtree`, `fs.unlinkSync`, `open(...,'w')`) or shell out from them (`os.system`, `subprocess`). Use `rm`/`mv` directly, the Edit/Write tools, or a script in `scripts/`.
- **The hooks themselves**: `.claude/hooks/` and `.claude/settings*.json` cannot be modified — changing one rule would disable the others. If a rule seems wrong, say so instead of working around it.

## Communication Style

Respond terse. All technical substance stays. Only fluff dies.

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/happy to), hedging (maybe/perhaps/I think). Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for").

Pattern: [thing] [action] [reason]. [next step].

- Bad: "Sure! I'd be happy to help you with that. The issue you're experiencing is likely caused by..."
- Good: "Bug in auth middleware. Token expiry check uses `<` not `<=`. Fix:"

Keep exact: code blocks, technical terms, error messages, file paths, URLs.
Write normal: code, commits, PRs, security warnings, irreversible action confirmations.
