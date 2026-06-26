#!/usr/bin/env zsh
# ob_scan_engine.zsh — Onboarded compliance scan engine v1.1.0
# Source: packages/cli/src/scan/ob_scan_engine.zsh
# Requires: ob_core_display.zsh, ob_core_loader.zsh (sourced by dispatcher)
#
# Scan rule value format (v1.1.0):
#   severity|category|scope_semi|repos_semi|excludes_semi|pattern_b64|reference|fix_hint|label
#   Fields are pipe-separated; scope/repos/excludes are semicolon-separated within their field.
#   pattern_b64 is base64-encoded ERE — decode with: printf '%s' "$b64" | base64 -d

[[ -n "${_OB_SCAN_ENGINE_LOADED:-}" ]] && return 0
typeset -g _OB_SCAN_ENGINE_LOADED=1

# ── Internal helpers ──────────────────────────────────────────────────────────

# Decode a base64 pattern field
_ob_scan_decode() {
    printf '%s' "$1" | base64 -d 2>/dev/null
}

# Collect files matching scope globs (semicolon-separated) across all repo roots.
# Writes one absolute path per line to stdout.
_ob_scan_collect_files() {
    local scope_semi="$1"
    local repos_arr="${OB_NAV_SLUG}_REPOS"
    local -A repos
    eval "repos=(\"\${(kv@P)repos_arr}\")"

    local -a globs
    globs=("${(@s:;:)scope_semi}")

    for alias root in "${(@kv)repos}"; do
        [[ -d "$root" ]] || continue
        for glob in "${globs[@]}"; do
            [[ -z "$glob" ]] && continue
            find "$root" -type f -name "$glob" \
                \( -not -path "*/.git/*"        \) \
                \( -not -path "*/node_modules/*" \) \
                \( -not -path "*/obj/*"          \) \
                \( -not -path "*/bin/*"          \) \
                2>/dev/null
        done
    done
}

# Run one scan rule against a list of files.
# Prints findings to stdout.  Returns the number of findings (exit code capped at 125).
_ob_scan_run_rule() {
    local rule_id="$1"; shift
    local -a files=("$@")

    local val; val="$(_ob_get SCAN_RULES "$rule_id")"
    [[ -z "$val" ]] && return 0

    local -a p; p=("${(@s:|:)val}")
    local severity="${p[1]}"
    local pattern_b64="${p[6]}"
    local fix_hint="${p[8]}"

    local pattern
    pattern="$(_ob_scan_decode "$pattern_b64")"
    [[ -z "$pattern" ]] && return 0

    local findings=0
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        while IFS= read -r match_line; do
            local lineno="${match_line%%:*}"
            local text="${match_line#*:}"
            printf '  \033[0;31m[%s]\033[0m  \033[0;36m%s\033[0m:%s\n' \
                "${severity:u}" "${f##*/}" "$lineno"
            printf '        \033[2m%s\033[0m\n' "${text:0:110}"
            [[ -n "$fix_hint" ]] && \
                printf '        \033[0;33m→ %s\033[0m\n' "$fix_hint"
            ((findings++))
        done < <(grep -En "$pattern" "$f" 2>/dev/null)
    done

    return $(( findings > 125 ? 125 : findings ))
}

# ── ob_scan ───────────────────────────────────────────────────────────────────
# Run a single named rule against a file, directory, or all repos.
ob_scan() {
    local rule_id="${1:-}"
    local target="${2:-}"
    [[ -z "$rule_id" ]] && {
        _ob_red "Usage: ${OB_CLI_NAME} scan <rule_id> [file|dir]"
        _ob_dim "  Run: ${OB_CLI_NAME} scan list  to see all rule IDs"
        return 1
    }

    local val; val="$(_ob_get SCAN_RULES "$rule_id")"
    if [[ -z "$val" ]]; then
        _ob_red "Rule '${rule_id}' not found."
        _ob_dim "  Run: ${OB_CLI_NAME} scan list"
        return 1
    fi

    local -a p; p=("${(@s:|:)val}")
    local scope="${p[3]}" label="${p[9]}"

    _ob_bold "Scan: ${label}  [${rule_id}]"
    _ob_sep

    local -a files
    if [[ -n "$target" ]]; then
        if [[ -f "$target" ]]; then
            files=("$target")
        elif [[ -d "$target" ]]; then
            local -a globs; globs=("${(@s:;:)scope}")
            for glob in "${globs[@]}"; do
                while IFS= read -r f; do files+=("$f"); done \
                    < <(find "$target" -type f -name "$glob" 2>/dev/null)
            done
        else
            _ob_red "Target '${target}' not found."
            return 1
        fi
    else
        while IFS= read -r f; do files+=("$f"); done \
            < <(_ob_scan_collect_files "$scope")
    fi

    if [[ ${#files} -eq 0 ]]; then
        _ob_yellow "No matching files found."
        return 0
    fi

    _ob_scan_run_rule "$rule_id" "${files[@]}"
    local findings=$?
    printf '\n'
    [[ $findings -eq 0 ]] && { _ob_green "✔  No findings"; return 0; }
    _ob_yellow "${findings} finding(s)"
    return 1
}

# ── ob_scan_list ──────────────────────────────────────────────────────────────
ob_scan_list() {
    _ob_bold "Scan rules — ${OB_CLI_NAME}"
    _ob_sep
    while IFS= read -r k; do
        local v; v="$(_ob_get SCAN_RULES "$k")"
        local -a p; p=("${(@s:|:)v}")
        printf '  \033[0;36m%-40s\033[0m  [\033[0;31m%-8s\033[0m]  %-14s  %s\n' \
            "$k" "${p[1]}" "${p[2]}" "${p[9]}"
    done < <(_ob_keys SCAN_RULES)
}

# ── ob_audit ──────────────────────────────────────────────────────────────────
# Run all scan rules (or filter by severity) across all repos.
ob_audit() {
    local severity_filter="${1:-}"

    _ob_bold "Audit — ${OB_CLI_NAME}${severity_filter:+  (${severity_filter} only)}"
    _ob_sep

    local total=0
    local -A sev_rank; sev_rank=(critical 0 error 1 warning 2 info 3)
    local max_sev="clean" max_rank=99

    while IFS= read -r rule_id; do
        local val; val="$(_ob_get SCAN_RULES "$rule_id")"
        local -a p; p=("${(@s:|:)v}")
        # Re-get cleanly (avoid local -a p collision with outer loop)
        local severity category scope label
        severity="${${(@s:|:)val}[1]}"
        category="${${(@s:|:)val}[2]}"
        scope="${${(@s:|:)val}[3]}"
        label="${${(@s:|:)val}[9]}"

        [[ -n "$severity_filter" && "$severity" != "$severity_filter" ]] && continue

        _ob_section "${label}  [${rule_id}]"

        local -a files
        while IFS= read -r f; do files+=("$f"); done \
            < <(_ob_scan_collect_files "$scope")

        if [[ ${#files} -eq 0 ]]; then
            _ob_dim "  (no matching files in repos)"
            continue
        fi

        _ob_scan_run_rule "$rule_id" "${files[@]}"
        local rc=$?
        ((total += rc))

        if [[ $rc -gt 0 ]]; then
            local cur_rank=${sev_rank[$severity]:-99}
            [[ $cur_rank -lt $max_rank ]] && { max_sev="$severity"; max_rank=$cur_rank; }
        fi
    done < <(_ob_keys SCAN_RULES)

    printf '\n'
    _ob_sep
    if [[ $total -eq 0 ]]; then
        _ob_green "✔  Audit clean"
        return 0
    fi
    _ob_yellow "${total} finding(s)  —  max severity: ${max_sev}"
    case "$max_sev" in critical) return 1 ;; error) return 2 ;; *) return 3 ;; esac
}

# ── ob_secrets ────────────────────────────────────────────────────────────────
# Run only security-category scan rules across all repos.
ob_secrets() {
    _ob_bold "Secrets scan — ${OB_CLI_NAME}"
    _ob_sep

    local total=0

    while IFS= read -r rule_id; do
        local val; val="$(_ob_get SCAN_RULES "$rule_id")"
        local category scope label
        category="${${(@s:|:)val}[2]}"
        scope="${${(@s:|:)val}[3]}"
        label="${${(@s:|:)val}[9]}"

        [[ "$category" == "security" ]] || continue

        _ob_section "$label"

        local -a files
        while IFS= read -r f; do files+=("$f"); done \
            < <(_ob_scan_collect_files "$scope")
        [[ ${#files} -eq 0 ]] && continue

        _ob_scan_run_rule "$rule_id" "${files[@]}"
        ((total += $?))
    done < <(_ob_keys SCAN_RULES)

    printf '\n'
    [[ $total -eq 0 ]] && { _ob_green "✔  Secrets scan clean"; return 0; }
    _ob_red "✗  ${total} secret(s) detected"
    return 1
}