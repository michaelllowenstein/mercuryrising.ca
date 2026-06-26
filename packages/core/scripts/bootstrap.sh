#!/usr/bin/env zsh
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — Onboarded v1.0.0 installer
#
# Usage:
#   ./scripts/bootstrap.sh              — install generic tenant
#   ./scripts/bootstrap.sh --tenant msi — install MSI tenant
#   ./scripts/bootstrap.sh --tenant msi --root ~/code
#
# What it does:
#   1. Detects Python (prefers py.exe on Windows, filters WindowsApps stubs)
#   2. Validates the tenant domain.json
#   3. Generates adapter files
#   4. Injects the source block into ~/.zshrc / ~/.bashrc
#   5. Prints the profile block (for manual review)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

TENANT="${OB_INSTALL_TENANT:-generic}"
OB_ROOT_OVERRIDE=""
SCRIPT_DIR="${0:A:h}"
MONO_ROOT="${SCRIPT_DIR:h:h:h}"
REPO_ROOT="$MONO_ROOT"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tenant) TENANT="$2"; shift 2 ;;
        --root)   OB_ROOT_OVERRIDE="$2"; shift 2 ;;
        *) print "Unknown arg: $1"; exit 1 ;;
    esac
done

# ── Detect Python ─────────────────────────────────────────────────────────────
_find_python() {
    # Prefer py.exe (Python Launcher, Windows) — avoids WindowsApps stubs
    if command -v py.exe &>/dev/null; then
        printf 'py.exe'
        return
    fi
    # Filter WindowsApps from PATH candidates
    local candidate
    for candidate in python3 python; do
        local resolved
        resolved="$(command -v "$candidate" 2>/dev/null || true)"
        [[ -z "$resolved" ]] && continue
        [[ "$resolved" == *WindowsApps* ]] && continue
        if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)" 2>/dev/null; then
            printf '%s' "$candidate"
            return
        fi
    done
    print "ERROR: Python 3.9+ not found. Install from https://python.org" >&2
    exit 1
}

PYTHON="$(_find_python)"
print "  Python: $PYTHON ($(${PYTHON} --version 2>&1))"

# ── Validate ──────────────────────────────────────────────────────────────────
print "  Validating tenant '${TENANT}'..."
"$PYTHON" "${MONO_ROOT}/packages/core/scripts/validate_domain.py" --tenant "$TENANT"

# ── Generate adapters ─────────────────────────────────────────────────────────
print "  Generating adapters..."
"$PYTHON" "${MONO_ROOT}/packages/core/scripts/generate_adapters.py" --tenant "$TENANT"

# ── Shell profile injection ───────────────────────────────────────────────────
OB_ROOT_VALUE="${OB_ROOT_OVERRIDE:-${OB_ROOT:-$HOME/repos}}"
CLI_NAME="$(${PYTHON} -c "
import json, pathlib
d = json.loads(pathlib.Path('${MONO_ROOT}/packages/core/tenants/${TENANT}/domain/domain.json').read_text())
print(d['tenant']['cli_name'])
")"

PROFILE_FILE="${ZDOTDIR:-$HOME}/.zshrc"
[[ -f "${HOME}/.bashrc" && ! -f "${HOME}/.zshrc" ]] && PROFILE_FILE="${HOME}/.bashrc"

BLOCK_START="# ── Onboarded (${TENANT}) ──"
BLOCK_END="# ── /Onboarded ──"

INJECT_BLOCK="${BLOCK_START}
export OB_ROOT=\"${OB_ROOT_VALUE}\"
export OB_TENANT=\"${TENANT}\"
export OB_EDITOR=\"\${OB_EDITOR:-code}\"
source \"${REPO_ROOT}/src/ob_dispatcher.zsh\"
${BLOCK_END}"

print "\n  Profile block to inject into ${PROFILE_FILE}:"
print "  ─────────────────────────────────────────────"
print "$INJECT_BLOCK"
print "  ─────────────────────────────────────────────"

# Check if already injected
if grep -q "$BLOCK_START" "$PROFILE_FILE" 2>/dev/null; then
    print "  ⚠  Block already present in ${PROFILE_FILE} — skipping injection"
    print "  ✔  Update complete. Reload shell: source ${PROFILE_FILE}"
else
    printf '\n%s\n' "$INJECT_BLOCK" >> "$PROFILE_FILE"
    print "  ✔  Injected into ${PROFILE_FILE}"
    print "     Reload: source ${PROFILE_FILE}"
fi

print ""
print "  Installation complete."
print "  Run: ${CLI_NAME} help"
print ""
