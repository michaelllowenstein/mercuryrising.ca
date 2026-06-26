#!/usr/bin/env zsh
# ============================================================================
# ob_learn.zsh — Shell-native implementation of `ob learn`
#
# Provides the `ob_learn` function which records an explicit path-to-operation
# association from the developer's terminal session and writes it to
# suggestions.json.  Mirrors the Python CLI command `ob-feedback learn where`
# but works entirely from Zsh for inline use during normal dev workflow.
#
# Usage:
#   ob_learn where <operation_key> <REPO_ALIAS:rel/path> [--role services]
#
# Example (after `msi where bind` returns a partial result):
#   msi learn where bind MSI-PAS:AdminPortal/Controllers/PolicyBindController.cs
#   msi learn where payment MSI-CORE:Services/PaymentRefundService.cs --role services
#
# Installation:
#   Sourced by ob_telemetry.zsh automatically, or add to ~/.zshrc:
#     source /path/to/packages/feedback/shell/ob_learn.zsh
#
# Integration note:
#   At merge time, ob_learn() is registered as a sub-command of ob_dispatcher.zsh
#   so `{tenant} learn where ...` works as a first-class ob command.
# ============================================================================

[[ -n "${_OB_LEARN_LOADED:-}" ]] && return 0
typeset -g _OB_LEARN_LOADED=1

ob_learn() {
    local subcmd="${1:-}"

    case "${subcmd}" in
        where)
            _ob_learn_where "${@:2}"
            ;;
        *)
            echo "Usage: ob learn where <operation> <REPO:path> [--role controllers|services|queues|js_entry]" >&2
            return 1
            ;;
    esac
}

_ob_learn_where() {
    local operation="${1:-}"
    local encoded_path="${2:-}"
    local role="controllers"

    # Parse optional --role flag
    local i
    for (( i=3; i<=$#; i++ )); do
        if [[ "${@[i]}" == "--role" ]]; then
            role="${@[i+1]:-controllers}"
            break
        fi
    done

    # Validate inputs
    if [[ -z "${operation}" || -z "${encoded_path}" ]]; then
        echo "Usage: ob learn where <operation> <REPO:path> [--role controllers|services|queues|js_entry]" >&2
        return 1
    fi

    if [[ "${encoded_path}" != *:* ]]; then
        echo "  ✗  Path must be in REPO_ALIAS:relative/path format. Got: '${encoded_path}'" >&2
        return 1
    fi

    if [[ ! "${role}" =~ ^(controllers|services|queues|js_entry)$ ]]; then
        echo "  ✗  Invalid role: '${role}'. Must be one of: controllers, services, queues, js_entry" >&2
        return 1
    fi

    local tenant="${OB_NAV_SLUG:-unknown}"

    # Delegate to Python CLI (most reliable path manipulation is in Python)
    if (( $+commands[ob-feedback] )); then
        ob-feedback learn where \
            --tenant "${tenant}" \
            --role "${role}" \
            "${operation}" "${encoded_path}"
        return $?
    fi

    # Fallback: shell-native JSON write (minimal, no difflib — just append)
    _ob_learn_shell_fallback "${tenant}" "${operation}" "${encoded_path}" "${role}"
}

_ob_learn_shell_fallback() {
    # Pure Zsh fallback when ob-feedback CLI is not available.
    # Writes a minimal suggestions.json entry without the full Python logic.
    local tenant="${1}"
    local operation="${2}"
    local encoded_path="${3}"
    local role="${4}"

    local suggestions_dir="${HOME}/.onboarded/${tenant}"
    local suggestions_file="${suggestions_dir}/suggestions.json"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

    mkdir -p "${suggestions_dir}"

    # If suggestions.json doesn't exist, create a minimal one
    if [[ ! -f "${suggestions_file}" ]]; then
        cat > "${suggestions_file}" <<JSONEOF
{
  "tenant": "${tenant}",
  "schema_version": "1.0.0",
  "generated": "${ts}",
  "operation_paths": [],
  "stale_paths": [],
  "missing_operations": [],
  "scan_rule_tuning": []
}
JSONEOF
    fi

    # Append to operation_paths using Python (available on any macOS/Linux with Python 3)
    python3 - <<PYEOF
import json, sys
from pathlib import Path

p = Path("${suggestions_file}")
data = json.loads(p.read_text())

# Dedup check
for existing in data.get("operation_paths", []):
    if (existing.get("operation_key") == "${operation}"
            and existing.get("encoded_path") == "${encoded_path}"):
        print("  ⚠  Already in suggestions.json.")
        sys.exit(0)

data.setdefault("operation_paths", []).append({
    "operation_key": "${operation}",
    "path_role": "${role}",
    "encoded_path": "${encoded_path}",
    "source": "ob_learn",
    "confidence": "high",
    "rationale": "Explicitly recorded by developer via shell ob_learn()"
})
data["generated"] = "${ts}"
p.write_text(json.dumps(data, indent=2))
print(f"  ✓  Recorded: ${operation} → ${role} → ${encoded_path}")
print(f"     Saved to: ${suggestions_file}")
print( "     Run 'ob-feedback suggest show' to review all pending suggestions.")
print( "     Run 'ob-feedback suggest apply' to open domain.json with suggestions pre-filled.")
PYEOF
}

# ── Register as a sub-command alias under the tenant CLI ─────────────────────
#
# After ob_dispatcher.zsh registers the tenant alias (e.g. 'msi'), this block
# extends it to handle the 'learn' sub-command.
#
# Enables: `msi learn where bind MSI-PAS:path/to/file.cs`

_ob_register_learn_alias() {
    local alias_name="${OB_CLI_NAME:-${OB_NAV_SLUG:-onboarded}}"

    (( $+functions[${alias_name}] )) || return 0
    (( $+functions[_ob_learn_registered_${alias_name}] )) && return 0

    typeset -g "_ob_learn_registered_${alias_name}=1"

    # Capture current function body (which may already be wrapped by ob_telemetry.zsh)
    local current_body="${functions[${alias_name}]}"

    eval "
${alias_name}() {
    if [[ \"\${1:-}\" == 'learn' ]]; then
        ob_learn \"\${@:2}\"
        return \$?
    fi
    ${current_body}
}
"
}

_ob_register_learn_alias