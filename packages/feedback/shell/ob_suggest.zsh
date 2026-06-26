#!/usr/bin/env zsh
# ============================================================================
# ob_suggest.zsh — Shell-native suggest commands
#
# Provides the `ob_suggest_show` and `ob_suggest_apply` functions for
# inline terminal use, delegating to the Python CLI when available and
# falling back to a minimal shell implementation when not.
#
# Also registers 'suggest' and 'doctor' as sub-commands of the tenant alias.
#
# Usage:
#   msi suggest show
#   msi suggest apply
#   msi suggest operations
#   msi suggest git [--since "30 days ago"]
#   msi suggest rules
#   msi doctor
#
# Installation:
#   Add to ~/.zshrc after ob_telemetry.zsh and ob_learn.zsh:
#     source /path/to/packages/feedback/shell/ob_suggest.zsh
#
# Integration note:
#   At merge time these become registered sub-commands of ob_dispatcher.zsh
#   routing through the standard ob command surface.
# ============================================================================

[[ -n "${_OB_SUGGEST_LOADED:-}" ]] && return 0
typeset -g _OB_SUGGEST_LOADED=1

# ── Core functions ────────────────────────────────────────────────────────────

ob_suggest() {
    local subcmd="${1:-}"
    local tenant="${OB_NAV_SLUG:-unknown}"

    case "${subcmd}" in
        show)
            _ob_run_python suggest show --tenant "${tenant}"
            ;;
        apply)
            _ob_run_python suggest apply --tenant "${tenant}" "${@:2}"
            ;;
        operations)
            _ob_run_python suggest operations --tenant "${tenant}" "${@:2}"
            ;;
        git)
            _ob_run_python suggest git --tenant "${tenant}" "${@:2}"
            ;;
        rules)
            _ob_run_python suggest rules --tenant "${tenant}" "${@:2}"
            ;;
        clear)
            _ob_run_python suggest clear --tenant "${tenant}"
            ;;
        ""|help)
            echo "Usage: ${OB_CLI_NAME:-ob} suggest <subcommand> [options]"
            echo ""
            echo "  show        Show all pending suggestions"
            echo "  apply       Open domain.json with suggestions pre-filled as comments"
            echo "  operations  Surface missing operations from telemetry misses"
            echo "  git         Find new files in git history and suggest operation associations"
            echo "  rules       Analyse scan rule effectiveness"
            echo "  clear       Clear all pending suggestions"
            echo ""
            echo "Options (most subcommands):"
            echo "  --days N        Lookback window in days (default: 90)"
            echo "  --since REF     Git ref for 'git' subcommand (default: '30 days ago')"
            ;;
        *)
            echo "  ✗  Unknown suggest subcommand: '${subcmd}'" >&2
            echo "     Run '${OB_CLI_NAME:-ob} suggest help' for usage." >&2
            return 1
            ;;
    esac
}

ob_doctor() {
    local tenant="${OB_NAV_SLUG:-unknown}"
    _ob_run_python doctor --tenant "${tenant}" "$@"
}

# ── Python delegation ─────────────────────────────────────────────────────────

_ob_run_python() {
    # Delegate to ob-feedback CLI if available; otherwise surface a clear error.
    if (( $+commands[ob-feedback] )); then
        ob-feedback "$@"
        return $?
    fi

    # Fallback: try direct Python module invocation
    if python3 -c "import onboarded_feedback" &>/dev/null 2>&1; then
        python3 -m onboarded_feedback.cli.main "$@"
        return $?
    fi

    echo "  ✗  ob-feedback CLI not found." >&2
    echo "     Install with: pip install -e /path/to/packages/feedback --break-system-packages" >&2
    echo "     Or set OB_FEEDBACK_PYTHONPATH to the package src/ directory." >&2
    return 127
}

# ── Telemetry show shortcut ───────────────────────────────────────────────────

ob_telemetry_show() {
    local tenant="${OB_NAV_SLUG:-unknown}"
    _ob_run_python telemetry show --tenant "${tenant}" "$@"
}

# ── Register as sub-commands under the tenant alias ──────────────────────────

_ob_register_suggest_alias() {
    local alias_name="${OB_CLI_NAME:-${OB_NAV_SLUG:-onboarded}}"

    (( $+functions[${alias_name}] )) || return 0
    (( $+functions[_ob_suggest_registered_${alias_name}] )) && return 0

    typeset -g "_ob_suggest_registered_${alias_name}=1"

    local current_body="${functions[${alias_name}]}"

    eval "
${alias_name}() {
    case \"\${1:-}\" in
        suggest)
            ob_suggest \"\${@:2}\"
            return \$?
            ;;
        doctor)
            ob_doctor \"\${@:2}\"
            return \$?
            ;;
        telemetry)
            ob_telemetry_show \"\${@:2}\"
            return \$?
            ;;
    esac
    ${current_body}
}
"
}

_ob_register_suggest_alias

# ── Convenience completions ───────────────────────────────────────────────────
# Zsh tab completion for the feedback sub-commands.
# Only registered if zsh compinit has been called.

if (( $+functions[compdef] )); then
    _ob_feedback_complete() {
        local alias_name="${OB_CLI_NAME:-${OB_NAV_SLUG:-onboarded}}"
        local -a subcmds
        subcmds=(
            'suggest:Generate and review domain improvement suggestions'
            'doctor:Check domain paths for staleness'
            'telemetry:Show usage telemetry summary'
            'learn:Record an explicit path-to-operation association'
        )
        local -a suggest_subcmds
        suggest_subcmds=(
            'show:Display all pending suggestions'
            'apply:Open domain.json with suggestions as comments'
            'operations:Find missing operations from telemetry'
            'git:Scan git history for new files'
            'rules:Analyse scan rule effectiveness'
            'clear:Clear all pending suggestions'
        )

        case "${words[2]}" in
            suggest)
                _describe 'suggest subcommands' suggest_subcmds
                ;;
            *)
                _describe "${alias_name} subcommands" subcmds
                ;;
        esac
    }

    local _alias="${OB_CLI_NAME:-${OB_NAV_SLUG:-onboarded}}"
    compdef "_ob_feedback_complete" "${_alias}" 2>/dev/null || true
fi