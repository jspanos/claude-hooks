# =============================================================================
# bash-6-python-venv.sh — Rule: Python must run inside a venv; prefer uv
#
# Rationale:
#   • Bare 'python' may resolve to Python 2 on some systems — always use python3
#   • Global pip installs pollute the system; venvs keep deps reproducible
#   • 'uv' is faster, more reliable, and manages venvs + packages in one tool
#
# Allowed:
#   • uv run python / uv run python3        (uv manages the environment)
#   • .venv/bin/python / .venv/bin/python3  (explicit venv activation)
#   • python --version / python3 --version  (version queries, no side effects)
#   • python3 when .venv already exists     (allowed, advise uv run)
#
# Blocked:
#   • bare 'python' (not python3, not in venv)
#   • pip install / pip3 install → use 'uv add'
#   • python -m pip install        → use 'uv add'
#   • python[3] -m venv            → use 'uv venv'
#   • python3 (no .venv present)   → create venv first
# =============================================================================

bash_check_python_venv() {
  local cmd="$1"

  # Quick exit: not a python-related command
  printf '%s' "$cmd" | grep -qE '^\s*(python[23]?|pip[23]?)\b' || return 0

  # ── Always allow: version queries ────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*python[23]?\s+--version\b'; then
    return 0
  fi

  # ── Always allow: stdlib utility modules (no venv needed) ────────────────
  # These ship with Python and never import third-party packages.
  if printf '%s' "$cmd" | grep -qE '^\s*python[23]?\s+-m\s+(json\.tool|http\.server|zipfile|compileall|py_compile|timeit|calendar|base64|uuid|platform|sysconfig|site|ensurepip|tokenize|ast|dis|pdb|cProfile|profile|trace|unittest|doctest)\b'; then
    return 0
  fi

  # ── Always allow: uv run python... ───────────────────────────────────────
  # (uv run handles venv activation automatically)
  if printf '%s' "$cmd" | grep -qE '^\s*uv\s+run\s+python'; then
    return 0
  fi

  # ── Always allow: .venv/bin/python... ────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*(\.venv|venv)/bin/python'; then
    return 0
  fi

  # ── Check if uv is available for tailored advice ─────────────────────────
  local uv_available=false
  command -v uv &>/dev/null 2>&1 && uv_available=true

  # ── Check if a .venv already exists ──────────────────────────────────────
  local venv_exists=false
  if [[ -d "$CWD/.venv" || -d "$PROJECT_DIR/.venv" ]]; then
    venv_exists=true
  fi

  # ── Build setup advice based on environment state ─────────────────────────
  local setup_advice
  if $uv_available; then
    if $venv_exists; then
      setup_advice="Run: uv run python3 <script>   (or activate: source .venv/bin/activate)"
    else
      setup_advice="Run: uv venv && uv run python3 <script>   (uv will create .venv automatically)"
    fi
  else
    if $venv_exists; then
      setup_advice="Activate the venv first: source .venv/bin/activate && python3 <script>
  Consider installing uv for better package management: curl -LsSf https://astral.sh/uv/install.sh | sh"
    else
      setup_advice="Create a venv first: python3 -m venv .venv && source .venv/bin/activate
  Consider installing uv instead: curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi
  fi

  # ── Block: pip install / pip3 install ─────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*pip[23]?\s+(install|uninstall)\b'; then
    local pkg
    pkg="$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*pip[23]?[[:space:]]+(install|uninstall)[[:space:]]*//' | awk '{print $1}')"
    if $uv_available; then
      deny_and_log "bash-6" \
        "Use 'uv add ${pkg:-<package>}' instead of pip install. uv manages packages inside the project venv (.venv) automatically — no need to activate first."
    else
      deny_and_log "bash-6" \
        "pip install installs globally. ${setup_advice}"
    fi
  fi

  # ── Block: python -m pip install ──────────────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*python[23]?\s+-m\s+pip\s+(install|uninstall)\b'; then
    local pkg
    pkg="$(printf '%s' "$cmd" | sed -E 's/.*pip[[:space:]]+(install|uninstall)[[:space:]]*//' | awk '{print $1}')"
    if $uv_available; then
      deny_and_log "bash-6" \
        "Use 'uv add ${pkg:-<package>}' instead of 'python -m pip install'. uv manages the project venv automatically."
    else
      deny_and_log "bash-6" \
        "'python -m pip install' installs to the interpreter's global site-packages. ${setup_advice}"
    fi
  fi

  # ── Block: python -m venv / python3 -m venv ──────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*python[23]?\s+-m\s+venv\b'; then
    if $uv_available; then
      deny_and_log "bash-6" \
        "Use 'uv venv' instead of 'python -m venv'. uv creates the venv faster and integrates with 'uv add' / 'uv run' for a consistent workflow."
    else
      # python -m venv is acceptable without uv, just advise uv
      return 0
    fi
  fi

  # ── Block: bare 'python' (not python3) ───────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*python\s' || \
     printf '%s' "$cmd" | grep -qE '^\s*python$'; then
    deny_and_log "bash-6" \
      "Use 'python3' — bare 'python' may resolve to Python 2 on some systems.
${setup_advice}"
  fi

  # ── Block: python3 without a venv present ────────────────────────────────
  if printf '%s' "$cmd" | grep -qE '^\s*python3\b'; then
    if ! $venv_exists; then
      deny_and_log "bash-6" \
        "No .venv found. Running python3 globally installs deps to the system Python.
${setup_advice}"
    fi
    # .venv exists — allow but no need to block (could advise, but let it through)
  fi
}
