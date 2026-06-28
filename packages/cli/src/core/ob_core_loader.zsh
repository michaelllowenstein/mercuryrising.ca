#!/usr/bin/env zsh
# ob_core_loader.zsh — Onboarded tenant resolver + adapter loader v1.1.0
# Source: packages/cli/src/core/ob_core_loader.zsh

[[ -n "${_OB_LOADER_LOADED:-}" ]] && return 0
typeset -g _OB_LOADER_LOADED=1

_ob_load_tenant() {
    local tenant="${OB_TENANT:-msi}"
    local slug_upper="${tenant:u}"          # msi → MSI, generic → GENERIC

    # OB_NAV_SLUG is the prefix for every generated array name.
    # All engine functions use ${OB_NAV_SLUG}_OPS — never MSI_OPS directly.
    export OB_NAV_SLUG="$slug_upper"

    # Resolve repo root from this file's absolute path.
    # Chain: ob_core_loader.zsh → core/ → src/ → cli/ → packages/ → repo root
    local loader_path="${${(%):-%x}:A}"
    local repo_root="${loader_path:h:h:h:h}"

    local nav_maps="${repo_root}/packages/core/generated/${tenant}/nav_maps.zsh"
    local scan_rules="${repo_root}/packages/core/generated/${tenant}/scan_rules.zsh"

    if [[ ! -f "$nav_maps" ]]; then
        printf >&2 '\033[0;31monboarded:\033[0m generated maps not found for tenant "%s".\n' "$tenant"
        printf >&2 '  Run: python3 packages/core/scripts/generate_adapters.py --tenant %s\n' "$tenant"
        return 1
    fi

    source "$nav_maps"
    [[ -f "$scan_rules" ]] && source "$scan_rules"

    # OB_CLI_NAME and OB_BRAND_NAME are exported by nav_maps.zsh.
    # (Generator emits: export OB_CLI_NAME="msi")
    # Fall back gracefully if an older adapter doesn't export them.
    export OB_CLI_NAME="${OB_CLI_NAME:-$tenant}"
    export OB_BRAND_NAME="${OB_BRAND_NAME:-$tenant}"
}

# ── Array accessor helpers ────────────────────────────────────────────────────

# _ob_get SUFFIX key
# Returns the value of ${OB_NAV_SLUG}_SUFFIX[key]
# Example: _ob_get OPS bind  →  value of MSI_OPS[bind]
_ob_get() {
    local _arr="${OB_NAV_SLUG}_${1}" _key="${2}"
    eval "printf '%s' \"\${${_arr}[${_key}]}\""
}

# _ob_keys SUFFIX
# Prints all keys of ${OB_NAV_SLUG}_SUFFIX, sorted, one per line.
# Example: _ob_keys OPS  →  bind\ncancel\nendorse\n...
_ob_keys() {
    local _arr="${OB_NAV_SLUG}_${1}"
    eval "printf '%s\n' \"\${(ko@)${_arr}}\""
}