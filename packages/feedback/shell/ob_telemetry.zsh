#!/usr/bin/env zsh
# ============================================================================
# ob_telemetry.zsh — Onboarded feedback loop: telemetry collection hooks
#
# Purpose:
#   Wraps the existing Onboarded tenant alias (msi, onboarded, etc.) to
#   silently record command events after each invocation.  The original
#   command is always called first — telemetry never blocks or modifies
#   the command's output or exit code.
#
# Installation:
#   Add to ~/.zshrc AFTER sourcing the main ob dispatcher:
#
#     source /path/to/packages/cli/ob_dispatcher.zsh   # existing, unchanged
#     source /path/to/packages/feedback/shell/ob_telemetry.zsh   # this file
#
# Environment:
#   OB_NAV_SLUG        — tenant slug (already set by main dispatcher)
#   OB_FEEDBACK_QUIET  — set to '1' to suppress all feedback module output
#   OB_TELEMETRY_OFF   — set to '1' to disable telemetry entirely
#
# Privacy:
#   Only command names and lookup keys are logged.
#   No file content, no path values, no code, no repo names.
#   All data stays in ~/.onboarded/${tenant}/telemetry.db
#
# Integration note:
#   At merge time, _ob_record_event() is inlined into ob_nav_engine.zsh
#   and ob_scan_engine.zsh directly, replacing this wrapper approach.
# ============================================================================

# ── Guard: only load once ────────────────────────────────────────────────────
[[ -n "${_OB_TELEMETRY_LOADED:-}" ]] && return 0
typeset -g _OB_TELEMETRY_LOADED=1

# ── Guard: opt-out ───────────────────────────────────────────────────────────
[[ "${OB_TELEMETRY_OFF:-0}" == "1" ]] && return 0

# ── Telemetry write function ─────────────────────────────────────────────────

_ob_record_event() {
    # Usage: _ob_record_event <event_type> <command> <key> <result>
    # Runs python in the background; never blocks the shell.
    local event_type="${1}"
    local command="${2}"
    local key="${3:-}"
    local result="${4:-}"
    local tenant="${OB_NAV_SLUG:-unknown}"

    # ob-feedback must be on PATH; silently skip if not available.
    (( $+commands[ob-feedback] )) || return 0

    # Fire-and-forget: background job, all output suppressed.
    python3 - <<PYEOF &>/dev/null &
import sys, os
sys.path.insert(0, os.environ.get('OB_FEEDBACK_PYTHONPATH', ''))
try:
    from onboarded_feedback.telemetry.store import record_event, TelemetryEvent
    record_event(TelemetryEvent(
        event_type='${event_type}',
        tenant='${tenant}',
        command='${command}',
        key='${key}' or None,
        result='${result}' or None,
    ))
except Exception:
    pass
PYEOF
    disown 2>/dev/null || true
}

_ob_record_scan_event() {
    # Usage: _ob_record_scan_event <rule_id> <finding_count> [acted_on]
    local rule_id="${1}"
    local finding_count="${2:-0}"
    local acted_on="${3:-0}"
    local tenant="${OB_NAV_SLUG:-unknown}"

    (( $+commands[ob-feedback] )) || return 0

    python3 - <<PYEOF &>/dev/null &
import sys, os
sys.path.insert(0, os.environ.get('OB_FEEDBACK_PYTHONPATH', ''))
try:
    from onboarded_feedback.telemetry.store import record_scan_event
    record_scan_event(
        tenant='${tenant}',
        rule_id='${rule_id}',
        finding_count=${finding_count},
        acted_on=bool(${acted_on}),
    )
except Exception:
    pass
PYEOF
    disown 2>/dev/null || true
}

# ── Dispatcher wrapper ────────────────────────────────────────────────────────
#
# Strategy: capture the tenant alias function that ob_dispatcher.zsh registered
# (e.g. 'msi' or 'onboarded'), rename it, and replace it with a wrapper that
# calls the original then records telemetry.
#
# This runs at source time, so OB_NAV_SLUG and OB_CLI_NAME must already be set.

_ob_wrap_alias() {
    local alias_name="${OB_CLI_NAME:-${OB_NAV_SLUG:-onboarded}}"

    # The original function must exist before we can wrap it.
    if ! (( $+functions[${alias_name}] )); then
        return 0
    fi

    # Avoid double-wrapping.
    if (( $+functions[_ob_unwrapped_${alias_name}] )); then
        return 0
    fi

    # Capture the original function body.
    eval "_ob_unwrapped_${alias_name}() { ${functions[${alias_name}]} }"

    # Replace with wrapper.
    eval "
${alias_name}() {
    local _ob_cmd=\"\${1:-}\"
    local _ob_key=\"\${2:-}\"

    # Call the original command — this is always first.
    _ob_unwrapped_${alias_name} \"\$@\"
    local _ob_exit=\$?

    # Infer result from exit code and output indicators.
    # 0 = success (hit or partial), non-zero = miss for lookup commands.
    local _ob_result
    if [[ _ob_exit -eq 0 ]]; then
        _ob_result='hit'
    else
        _ob_result='miss'
    fi

    # Map command to event type.
    local _ob_event='command'
    [[ \"\${_ob_result}\" == 'miss' ]] && _ob_event='miss'

    _ob_record_event \"\${_ob_event}\" \"\${_ob_cmd}\" \"\${_ob_key}\" \"\${_ob_result}\"

    return \${_ob_exit}
}
"
}

_ob_wrap_alias

# ── Partial result detection ──────────────────────────────────────────────────
#
# The nav engine prints '○' for paths not found on disk (partial result).
# We hook into the output to detect this and log 'partial' instead of 'hit'.
# This is done by re-wrapping the alias to capture stdout and check for '○'.

_ob_wrap_with_partial_detection() {
    local alias_name="${OB_CLI_NAME:-${OB_NAV_SLUG:-onboarded}}"

    (( $+functions[${alias_name}] )) || return 0
    (( $+functions[_ob_partial_wrapped_${alias_name}] )) && return 0

    eval "_ob_partial_wrapped_${alias_name}() { ${functions[${alias_name}]} }"

    eval "
${alias_name}() {
    local _ob_cmd=\"\${1:-}\"
    local _ob_key=\"\${2:-}\"

    # Capture output to detect partial results while still printing to terminal
    local _ob_output
    _ob_output=\$(_ob_partial_wrapped_${alias_name} \"\$@\" 2>&1)
    local _ob_exit=\$?
    echo \"\${_ob_output}\"

    local _ob_result='hit'
    local _ob_event='command'

    if [[ _ob_exit -ne 0 ]]; then
        _ob_result='miss'
        _ob_event='miss'
    elif echo \"\${_ob_output}\" | grep -q '○'; then
        _ob_result='partial'
        _ob_event='command'
    fi

    _ob_record_event \"\${_ob_event}\" \"\${_ob_cmd}\" \"\${_ob_key}\" \"\${_ob_result}\"

    return \${_ob_exit}
}
"
}

_ob_wrap_with_partial_detection

# ── Scan result telemetry ─────────────────────────────────────────────────────
#
# Hooks into the scan commands to log per-rule finding counts.
# Called from ob_scan_engine.zsh after each rule runs (post-integration).
# Pre-integration: this function is available for manual use in your shell.

ob_telemetry_scan_result() {
    # Usage: ob_telemetry_scan_result <rule_id> <finding_count>
    _ob_record_scan_event "${1}" "${2:-0}" "0"
}

# ── Post-commit hook helper ───────────────────────────────────────────────────
#
# When a developer commits after a clean audit, set acted_on=1 for the
# most recent scan event.  Wire this into your git commit hook:
#   echo 'ob_telemetry_post_commit' >> .git/hooks/post-commit

ob_telemetry_post_commit() {
    local tenant="${OB_NAV_SLUG:-unknown}"
    local last_rules_file="${HOME}/.onboarded/${tenant}/.last_scan_rules"

    [[ -f "${last_rules_file}" ]] || return 0

    while IFS= read -r rule_id; do
        _ob_record_scan_event "${rule_id}" "0" "1"
    done < "${last_rules_file}"
}