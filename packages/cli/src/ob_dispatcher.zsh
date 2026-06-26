#!/usr/bin/env zsh
# ob_dispatcher.zsh — Onboarded v1.1.0 Unified CLI Dispatcher
#
# Add to ~/.zshrc (AFTER existing msi-nav source line for side-by-side testing):
#   export OB_TENANT=msi
#   source /path/to/onboarded/packages/cli/src/ob_dispatcher.zsh
#
# Optional — source feedback hooks after the dispatcher:
#   source /path/to/onboarded/packages/feedback/shell/ob_telemetry.zsh

[[ -n "${_OB_DISPATCHER_LOADED:-}" ]] && return 0
typeset -g _OB_DISPATCHER_LOADED=1

_OB_DISPATCHER_DIR="${${(%):-%x}:h}"

# Bootstrap: source engine files in dependency order.
_ob_bootstrap() {
    local base="$_OB_DISPATCHER_DIR"
    source "${base}/core/ob_core_display.zsh" || return 1
    source "${base}/core/ob_core_loader.zsh"  || return 1
    _ob_load_tenant                            || return 1
    source "${base}/nav/ob_nav_engine.zsh"    || return 1
    source "${base}/scan/ob_scan_engine.zsh"  || return 1
}

_ob_bootstrap || {
    printf >&2 '\033[0;31monboarded:\033[0m bootstrap failed — check OB_TENANT and generated adapters\n'
    return 1
}

# ── Main dispatch function ────────────────────────────────────────────────────
function global:onboarded() {
    local cmd="${1:l}"; shift 2>/dev/null
    case "$cmd" in
        where|w)         ob_where "$@" ;;
        status|s)        ob_status "$@" ;;
        product|prod|p)  ob_product "$@" ;;
        portal)          ob_portal "$@" ;;
        queue|qu)        ob_queue "$@" ;;
        explain|def|e)   ob_explain "$@" ;;
        grep|g)          ob_grep "$@" ;;
        list|l)          ob_list "$@" ;;
        cd)              ob_cd "$@" ;;
        doctor)          ob_doctor ;;
        scan)
            local sub="${1:-}"; shift 2>/dev/null
            case "$sub" in
                list|l|"") ob_scan_list ;;
                *)         ob_scan "$sub" "$@" ;;
            esac ;;
        audit|a)         ob_audit "$@" ;;
        secrets|sec)     ob_secrets "$@" ;;
        suggest)
            local sub="${1:-show}"; shift 2>/dev/null
            case "$sub" in
                show)
                    (( $+functions[ob_suggest_show] )) \
                        && ob_suggest_show \
                        || _ob_red "feedback package not loaded — source packages/feedback/shell/ob_suggest.zsh" ;;
                apply)
                    (( $+functions[ob_suggest_apply] )) \
                        && ob_suggest_apply \
                        || _ob_red "feedback package not loaded" ;;
                operations)
                    (( $+functions[ob_suggest_operations] )) \
                        && ob_suggest_operations \
                        || _ob_red "feedback package not loaded" ;;
                clear)
                    (( $+functions[ob_suggest_clear] )) \
                        && ob_suggest_clear \
                        || _ob_red "feedback package not loaded" ;;
                *)  _ob_red "Unknown suggest subcommand: $sub"; return 1 ;;
            esac ;;
        learn)
            (( $+functions[ob_learn] )) \
                && ob_learn "$@" \
                || _ob_red "feedback package not loaded — source packages/feedback/shell/ob_learn.zsh" ;;
        help|h|"")  _ob_help ;;
        *)
            _ob_red "Unknown command: '${cmd}'"
            _ob_dim "  Run: ${OB_CLI_NAME:-ob} help"
            return 1 ;;
    esac
}

_ob_help() {
    local n="${OB_CLI_NAME:-ob}"
    printf '\033[1m%s\033[0m  —  Onboarded platform intelligence CLI\n\n' "$n"
    printf '\033[0;36mNavigation\033[0m\n'
    printf '  %-34s %s\n' "${n} where <op>"              "Source files for a platform operation"
    printf '  %-34s %s\n' "${n} status [code]"            "Look up a status code"
    printf '  %-34s %s\n' "${n} explain [term]"           "Glossary definition + see-also"
    printf '  %-34s %s\n' "${n} product [id]"             "Product line — controllers, WebJobs, JS"
    printf '  %-34s %s\n' "${n} portal [name]"            "Portal URL and description"
    printf '  %-34s %s\n' "${n} queue [name]"             "Queue consumer and description"
    printf '  %-34s %s\n' "${n} list [ops|rules]"         "List all operations or scan rules"
    printf '  %-34s %s\n' "${n} grep <pattern>"           "Full-text search across all repos"
    printf '  %-34s %s\n' "${n} cd <REPO_ALIAS>"          "cd to a repo root"
    printf '\n\033[0;36mCompliance\033[0m\n'
    printf '  %-34s %s\n' "${n} audit"                    "All scan rules across all repos"
    printf '  %-34s %s\n' "${n} secrets"                  "Security-category rules only"
    printf '  %-34s %s\n' "${n} scan <rule_id> [path]"    "Single rule against a file or directory"
    printf '  %-34s %s\n' "${n} scan list"                "List all registered rule IDs"
    printf '\n\033[0;36mDomain health\033[0m\n'
    printf '  %-34s %s\n' "${n} doctor"                   "Repo presence + stale path check"
    printf '  %-34s %s\n' "${n} suggest show"             "Pending domain improvement suggestions"
    printf '  %-34s %s\n' "${n} suggest apply"            "Open domain.json with suggestions inlined"
    printf '  %-34s %s\n' "${n} suggest operations"       "Missing operations ranked by miss frequency"
    printf '  %-34s %s\n' "${n} learn where <op> <R:p>"  "Record a path→operation learning"
    printf '\n\033[2mShort aliases: w s p e l g a sec  |  ob obw obs oba obsec\033[0m\n'
}

# Register tenant alias.  cli_name="msi" → function msi() { onboarded "$@"; }
_ob_register_alias() {
    local cli="${OB_CLI_NAME:-onboarded}"
    if [[ "$cli" != "onboarded" ]]; then
        eval "function global:${cli}() { onboarded \"\$@\"; }"
        eval "alias ${cli}w='${cli} where'"
        eval "alias ${cli}s='${cli} status'"
        eval "alias ${cli}a='${cli} audit'"
        eval "alias ${cli}sec='${cli} secrets'"
    fi
}
_ob_register_alias

alias ob='onboarded'
alias obw='onboarded where'
alias obs='onboarded status'
alias oba='onboarded audit'
alias obsec='onboarded secrets'