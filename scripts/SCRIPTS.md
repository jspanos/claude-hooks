# Scripts Registry

This file is the **authoritative index** of all reusable scripts in this project.

**Before creating a new script:**
1. Check the Registry table below — a similar script may already exist
2. If it does, update it: add options, fix bugs, update docs — do not duplicate
3. If it does not, create a new one using the standard template

**Every script must:**
- Have a `--help` / `-h` flag that prints usage, options, and examples
- Start with `#!/usr/bin/env bash` and `set -euo pipefail` (or equivalent for Python)
- Be executable: `chmod +x scripts/<name>.sh`
- Have a row in the Registry table below

---

## Usage

```bash
# List available scripts
cat scripts/SCRIPTS.md

# Get help for any script
./scripts/<script-name>.sh --help

# Run a script
./scripts/<script-name>.sh [options] [args]
```

---

## Registry

| Script | Description | Key Options |
|--------|-------------|-------------|
| `scripts/deploy.sh` | Deploy hook scripts globally to `~/.claude/hooks/` or locally into a specific project | `--dry-run`, `--force`, `--no-claude-md`, `--local [path]` |

---

## Standard Script Template (bash)

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <required-arg>

Description:
  One sentence explaining what this script does.

Options:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output
  -n, --dry-run     Print actions without executing

Examples:
  $(basename "$0") foo
  $(basename "$0") --verbose bar

EOF
}

DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -n|--dry-run) DRY_RUN=true; shift ;;
    --)           shift; break ;;
    -*)           echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)            break ;;
  esac
done

main() {
  # Your script logic here
  echo "Running..."
}

main "$@"
```

## Standard Script Template (python)

```python
#!/usr/bin/env python3
"""
Script name — one sentence description.

Usage:
    ./scripts/<name>.py [options] <arg>
"""

import argparse
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).parent.parent


def main():
    parser = argparse.ArgumentParser(
        description="One sentence describing what this script does."
    )
    parser.add_argument("input", help="Description of required argument")
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("-n", "--dry-run", action="store_true")
    args = parser.parse_args()

    # Your script logic here


if __name__ == "__main__":
    main()
```
