#!/usr/bin/env zsh
# ob_core_display.zsh — Onboarded shared display utilities v1.1.0
# All functions prefixed _ob_ to avoid collision with user-defined functions.
# Source: packages/cli/src/core/ob_core_display.zsh

[[ -n "${_OB_DISPLAY_LOADED:-}" ]] && return 0
typeset -g _OB_DISPLAY_LOADED=1

# ── ANSI colour helpers ───────────────────────────────────────────────────────
_ob_red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
_ob_yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
_ob_cyan()   { printf '\033[0;36m%s\033[0m\n' "$*"; }
_ob_green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
_ob_dim()    { printf '\033[2m%s\033[0m\n'    "$*"; }
_ob_bold()   { printf '\033[1m%s\033[0m\n'    "$*"; }

# ── Structural print helpers ──────────────────────────────────────────────────
_ob_sep()    { printf '\033[2m────────────────────────────────────────────────────────────\033[0m\n'; }
_ob_kv()     { printf '  \033[0;36m%-22s\033[0m  %s\n' "$1" "$2"; }
_ob_kv_dim() { printf '  \033[0;36m%-22s\033[0m  \033[2m%s\033[0m\n' "$1" "$2"; }
_ob_section(){ printf '\n\033[0;36m  %s\033[0m\n' "$1"; }
_ob_bullet() { printf '  \033[2m•\033[0m  %s\n' "$1"; }

# ── Path display ──────────────────────────────────────────────────────────────
# Print one "REPO_ALIAS:rel/path" entry with ✔/○ disk-existence indicator.
# $1 = entry string (e.g. "MSI-PAS:AdminPortal/Controllers/BasePolicyController.cs")
# $2 = name of the slug's REPOS associative array  (e.g. "MSI_REPOS")
_ob_print_path() {
    local entry="$1" repos_arr="$2"
    if [[ "$entry" == *:* ]]; then
        local repo="${entry%%:*}"
        local rel="${entry#*:}"
        local root
        eval "root=\"\${${repos_arr}[${repo}]}\""
        if [[ -z "$root" ]]; then
            printf '  \033[2m○\033[0m  \033[2m%s\033[0m  \033[0;33m(repo not mapped)\033[0m\n' "$entry"
            return
        fi
        local abs="${root}/${rel}"
        if [[ -e "$abs" ]]; then
            printf '  \033[0;32m✔\033[0m  %s\n' "$abs"
        else
            printf '  \033[2m○\033[0m  \033[2m%s\033[0m  \033[0;31m(not found on disk)\033[0m\n' "$abs"
        fi
    else
        # Queue name or bare identifier — not a filesystem path
        printf '  \033[0;36m⇌\033[0m  %s\n' "$entry"
    fi
}

# Print a semicolon-separated list of path entries (v1.1.0 field format).
# $1 = "path1;path2;..."   $2 = REPOS array name
_ob_print_path_list() {
    local csv="$1" repos_arr="$2"
    [[ -z "$csv" ]] && return
    local -a entries
    entries=("${(@s:;:)csv}")
    for e in "${entries[@]}"; do
        [[ -n "$e" ]] && _ob_print_path "$e" "$repos_arr"
    done
}