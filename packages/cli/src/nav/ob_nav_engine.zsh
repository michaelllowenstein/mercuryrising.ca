#!/usr/bin/env zsh
# ob_nav_engine.zsh — Onboarded navigation commands v1.1.0
# Source: packages/cli/src/nav/ob_nav_engine.zsh
# Requires: ob_core_display.zsh, ob_core_loader.zsh (sourced by dispatcher)
#
# Generated array value formats (v1.1.0):
#   OPS:      label || ctrl1;ctrl2 || svc1;svc2 || queue1;queue2 || js1;js2
#   STATUS:   plain string
#   GLOSSARY: label | definition | see_also1;see_also2
#   PRODUCTS: label | code | ctrl1;ctrl2 | gen3_1;gen3_2 | js1;js2 | wj1;wj2
#   PORTALS:  name | path | prod1;prod2
#   QUEUES:   consumer | wj1;wj2
#   GLOSSARY_XREFS:  plain string (code path)
#   STATUS_TRIGGERS: plain string (trigger description)

[[ -n "${_OB_NAV_ENGINE_LOADED:-}" ]] && return 0
typeset -g _OB_NAV_ENGINE_LOADED=1

# ── ob_where ──────────────────────────────────────────────────────────────────
ob_where() {
    local key="${1:-}"
    [[ -z "$key" ]] && { _ob_red "Usage: ${OB_CLI_NAME} where <operation>"; return 1; }

    local val; val="$(_ob_get OPS "$key")"
    if [[ -z "$val" ]]; then
        _ob_red "Operation '${key}' not found."
        return 1
    fi

    local repos_arr="${OB_NAV_SLUG}_REPOS"

    # Split on double-pipe  (v1.1.0 OPS field separator)
    local -a p
    p=("${(@s:||:)val}")
    local label="${p[1]}"
    local ctrl_str="${p[2]}"
    local svc_str="${p[3]}"
    local queue_str="${p[4]}"
    local js_str="${p[5]}"

    _ob_bold "${key}  —  ${label}"
    _ob_sep

    [[ -n "$ctrl_str"  ]] && { _ob_section "Controllers";    _ob_print_path_list "$ctrl_str"  "$repos_arr"; }
    [[ -n "$svc_str"   ]] && { _ob_section "Services";       _ob_print_path_list "$svc_str"   "$repos_arr"; }
    [[ -n "$js_str"    ]] && { _ob_section "JavaScript";     _ob_print_path_list "$js_str"    "$repos_arr"; }
    if [[ -n "$queue_str" ]]; then
        _ob_section "Message queues"
        local -a qnames; qnames=("${(@s:;:)queue_str}")
        for q in "${qnames[@]}"; do [[ -n "$q" ]] && _ob_bullet "$q"; done
    fi

    # Show code path if GLOSSARY_XREFS has an entry for this operation
    local xref; xref="$(_ob_get GLOSSARY_XREFS "$key" 2>/dev/null)"
    if [[ -n "$xref" ]]; then
        _ob_section "Code path"
        printf '  \033[2m%s\033[0m\n' "$xref"
    fi

    return 0
}

# ── ob_status ─────────────────────────────────────────────────────────────────
ob_status() {
    local code="${1:-}"
    if [[ -z "$code" ]]; then
        _ob_bold "Status codes — ${OB_CLI_NAME}"
        _ob_sep
        while IFS= read -r k; do
            local v; v="$(_ob_get STATUS "$k")"
            local trigger; trigger="$(_ob_get STATUS_TRIGGERS "$k" 2>/dev/null)"
            printf '  \033[0;36m%-6s\033[0m  %-36s  \033[2m%s\033[0m\n' \
                "$k" "$v" "${trigger:0:60}"
        done < <(_ob_keys STATUS)
        return 0
    fi

    local desc; desc="$(_ob_get STATUS "$code")"
    if [[ -z "$desc" ]]; then
        _ob_red "Status code '${code}' not found."
        return 1
    fi
    printf '\n  \033[0;36m%-6s\033[0m  \033[1m%s\033[0m\n' "$code" "$desc"

    local trigger; trigger="$(_ob_get STATUS_TRIGGERS "$code" 2>/dev/null)"
    [[ -n "$trigger" ]] && printf '  \033[2m%-6s  %s\033[0m\n' "" "$trigger"
    printf '\n'
    return 0
}

# ── ob_explain ────────────────────────────────────────────────────────────────
ob_explain() {
    local term="${1:-}"
    if [[ -z "$term" ]]; then
        _ob_bold "Glossary — ${OB_CLI_NAME}"
        _ob_sep
        while IFS= read -r k; do
            local v; v="$(_ob_get GLOSSARY "$k")"
            local -a p; p=("${(@s:|:)v}")
            printf '  \033[0;36m%-22s\033[0m  %s\n' "$k" "${p[1]}"
        done < <(_ob_keys GLOSSARY)
        return 0
    fi

    local val; val="$(_ob_get GLOSSARY "$term")"
    if [[ -z "$val" ]]; then
        _ob_red "Term '${term}' not found."
        return 1
    fi

    # Format: label|definition|see_also_semi
    local -a p; p=("${(@s:|:)val}")
    local lbl="${p[1]}" defn="${p[2]}" see="${p[3]}"

    _ob_bold "$lbl"
    _ob_sep
    printf '  %s\n' "$defn"

    if [[ -n "$see" ]]; then
        printf '\n'
        _ob_kv_dim "See also:" "${see//;/, }"
    fi

    # Show code path from GLOSSARY_XREFS if present
    local xref; xref="$(_ob_get GLOSSARY_XREFS "$term" 2>/dev/null)"
    if [[ -n "$xref" ]]; then
        printf '\n'
        _ob_kv_dim "Code path:" "$xref"
    fi

    printf '\n'
    return 0
}

# ── ob_product ────────────────────────────────────────────────────────────────
ob_product() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        _ob_bold "Products — ${OB_CLI_NAME}"
        _ob_sep
        while IFS= read -r k; do
            local v; v="$(_ob_get PRODUCTS "$k")"
            local -a p; p=("${(@s:|:)v}")
            printf '  \033[0;36m%-20s\033[0m  [%-4s]  %s\n' "$k" "${p[2]}" "${p[1]}"
        done < <(_ob_keys PRODUCTS)
        return 0
    fi

    local val; val="$(_ob_get PRODUCTS "$id")"
    [[ -z "$val" ]] && { _ob_red "Product '${id}' not found."; return 1; }

    # Format: label|code|ctrl_semi|gen3_semi|js_semi|webjobs_semi
    local -a p; p=("${(@s:|:)val}")
    local label="${p[1]}" code="${p[2]}"
    local ctrl_str="${p[3]}" gen3_str="${p[4]}" js_str="${p[5]}" wj_str="${p[6]}"
    local repos_arr="${OB_NAV_SLUG}_REPOS"

    _ob_bold "${id}  —  ${label}${code:+  \033[2m(code ${code})\033[0m}"
    _ob_sep

    [[ -n "$ctrl_str" ]] && { _ob_section "Controllers";      _ob_print_path_list "$ctrl_str" "$repos_arr"; }
    [[ -n "$gen3_str" ]] && { _ob_section "Gen3 / API";       _ob_print_path_list "$gen3_str" "$repos_arr"; }
    if [[ -n "$js_str" ]]; then
        _ob_section "JS widgets"
        local -a jnames; jnames=("${(@s:;:)js_str}")
        for j in "${jnames[@]}"; do [[ -n "$j" ]] && _ob_bullet "$j"; done
    fi
    if [[ -n "$wj_str" ]]; then
        _ob_section "WebJobs"
        local -a wnames; wnames=("${(@s:;:)wj_str}")
        for w in "${wnames[@]}"; do [[ -n "$w" ]] && _ob_bullet "$w"; done
    fi
    return 0
}

# ── ob_portal ─────────────────────────────────────────────────────────────────
ob_portal() {
    local name="${1:-}"
    local repos_arr="${OB_NAV_SLUG}_REPOS"

    if [[ -z "$name" ]]; then
        _ob_bold "Portals — ${OB_CLI_NAME}"
        _ob_sep
        while IFS= read -r k; do
            local v; v="$(_ob_get PORTALS "$k")"
            local -a p; p=("${(@s:|:)v}")
            # p[1]=name  p[2]=REPO:path  p[3]=products_semi
            printf '  \033[0;36m%-24s\033[0m  %-18s  %s\n' "$k" "${p[1]}" "${p[2]}"
        done < <(_ob_keys PORTALS)
        return 0
    fi

    local val; val="$(_ob_get PORTALS "$name")"
    [[ -z "$val" ]] && { _ob_red "Portal '${name}' not found."; return 1; }

    # Format: name|REPO_ALIAS:rel/path|products_semi
    local -a p; p=("${(@s:|:)val}")
    # Note: REPO:path itself contains a colon, so we rejoin p[2..] up to the
    # products field.  Generator emits name|REPO:path|products, meaning the
    # split on | gives: p[1]=name  p[2]=REPO  p[3]=rel/path  p[4]=products
    # Reconstruct the path spec:
    local portal_name="${p[1]}"
    local repo_alias="${p[2]}"
    local rel_path="${p[3]}"
    local products_semi="${p[4]}"
    local path_spec="${repo_alias}:${rel_path}"

    _ob_bold "${name}  —  ${portal_name}"
    _ob_sep
    _ob_section "Path"
    _ob_print_path "$path_spec" "$repos_arr"
    if [[ -n "$products_semi" ]]; then
        _ob_section "Products"
        local -a prods; prods=("${(@s:;:)products_semi}")
        for pr in "${prods[@]}"; do [[ -n "$pr" ]] && _ob_bullet "$pr"; done
    fi
    return 0
}

# ── ob_queue ──────────────────────────────────────────────────────────────────
ob_queue() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        _ob_bold "Message queues — ${OB_CLI_NAME}"
        _ob_sep
        while IFS= read -r k; do
            local v; v="$(_ob_get QUEUES "$k")"
            local -a p; p=("${(@s:|:)v}")
            # p[1]=label  p[2]=consumer  p[3]=webjobs  p[4]=description
            printf '  \033[0;36m%-44s\033[0m  %s\n' "$k" "${p[1]}"
        done < <(_ob_keys QUEUES)
        return 0
    fi

    local val; val="$(_ob_get QUEUES "$name")"
    [[ -z "$val" ]] && { _ob_red "Queue '${name}' not found."; return 1; }

    # Format: label|consumer|webjobs|description
    local -a p; p=("${(@s:|:)v}")
    local -a p; p=("${(@s:|:)val}")
    _ob_bold "$name  —  ${p[1]}"
    _ob_sep
    [[ -n "${p[2]}" ]] && _ob_kv "Consumer:" "${p[2]}"
    [[ -n "${p[3]}" ]] && _ob_kv "WebJob:"   "${p[3]}"
    [[ -n "${p[4]}" ]] && _ob_kv_dim "Description:" "${p[4]}"
    return 0
}

# ── ob_list ───────────────────────────────────────────────────────────────────
ob_list() {
    local what="${1:-ops}"
    case "$what" in
        ops|operations|"")
            _ob_bold "Operations — ${OB_CLI_NAME}"
            _ob_sep
            while IFS= read -r k; do
                local v; v="$(_ob_get OPS "$k")"
                # label is everything before the first ||
                local label="${v%%||*}"
                printf '  \033[0;36m%-28s\033[0m  %s\n' "$k" "$label"
            done < <(_ob_keys OPS) ;;
        rules)
            _ob_bold "Scan rules — ${OB_CLI_NAME}"
            _ob_sep
            while IFS= read -r k; do
                local v; v="$(_ob_get SCAN_RULES "$k")"
                local -a p; p=("${(@s:|:)v}")
                # p[1]=severity  p[2]=category  p[9]=label
                printf '  \033[0;36m%-38s\033[0m  [\033[0;31m%-8s\033[0m]  %s  —  %s\n' \
                    "$k" "${p[1]}" "${p[2]}" "${p[9]}"
            done < <(_ob_keys SCAN_RULES) ;;
        *)
            _ob_red "Unknown list target '${what}'. Use: ops | rules"
            return 1 ;;
    esac
}

# ── ob_grep ───────────────────────────────────────────────────────────────────
ob_grep() {
    local pattern="${1:-}"
    [[ -z "$pattern" ]] && { _ob_red "Usage: ${OB_CLI_NAME} grep <pattern>"; return 1; }

    local repos_arr="${OB_NAV_SLUG}_REPOS"
    local -A repos
    eval "repos=(\"\${(kv@P)repos_arr}\")"

    _ob_bold "Searching: ${pattern}"
    _ob_sep

    local found=0
    for alias root in "${(@kv)repos}"; do
        [[ -d "$root" ]] || continue
        local hits
        if command -v rg &>/dev/null; then
            hits=$(rg --color=never -l "$pattern" "$root" 2>/dev/null)
        else
            hits=$(grep -rl "$pattern" "$root" 2>/dev/null)
        fi
        if [[ -n "$hits" ]]; then
            _ob_section "$alias"
            while IFS= read -r f; do
                _ob_bullet "${f#${root}/}"
                ((found++))
            done <<< "$hits"
        fi
    done

    [[ $found -eq 0 ]] && { _ob_yellow "No matches found."; return 1; }
    return 0
}

# ── ob_cd ─────────────────────────────────────────────────────────────────────
ob_cd() {
    local target="${1:-}"
    [[ -z "$target" ]] && { _ob_red "Usage: ${OB_CLI_NAME} cd <REPO_ALIAS>"; return 1; }

    local repos_arr="${OB_NAV_SLUG}_REPOS"
    local -A repos
    eval "repos=(\"\${(kv@P)repos_arr}\")"
    local root="${repos[$target]}"

    [[ -z "$root" ]]   && { _ob_red "Repo alias '${target}' not found."; return 1; }
    [[ ! -d "$root" ]] && { _ob_red "Repo '${root}' does not exist on disk."; return 1; }
    cd "$root"
}

# ── ob_doctor ─────────────────────────────────────────────────────────────────
ob_doctor() {
    local repos_arr="${OB_NAV_SLUG}_REPOS"
    local -A repos
    eval "repos=(\"\${(kv@P)repos_arr}\")"

    _ob_bold "Onboarded doctor — tenant: ${OB_TENANT:-${OB_NAV_SLUG:l}}"
    _ob_sep

    _ob_section "Repository roots"
    local all_ok=1
    for alias root in "${(@kv)repos}"; do
        if [[ -d "$root" ]]; then
            printf '  \033[0;32m✔\033[0m  %-20s  \033[2m%s\033[0m\n' "$alias" "$root"
        else
            printf '  \033[2m○\033[0m  %-20s  \033[0;31m%s  (not found)\033[0m\n' "$alias" "$root"
            all_ok=0
        fi
    done

    _ob_section "Operation path check"
    local stale=0
    while IFS= read -r op; do
        local val; val="$(_ob_get OPS "$op")"
        local -a parts; parts=("${(@s:||:)val}")
        # Check controllers (parts[2]) and services (parts[3])
        for field_str in "${parts[2]}" "${parts[3]}"; do
            [[ -z "$field_str" ]] && continue
            local -a paths; paths=("${(@s:;:)field_str}")
            for p in "${paths[@]}"; do
                [[ -z "$p" || "$p" != *:* ]] && continue
                local repo="${p%%:*}" rel="${p#*:}"
                local root; eval "root=\"\${${repos_arr}[$repo]}\""
                [[ -z "$root" ]] && continue
                [[ ! -e "${root}/${rel}" ]] && {
                    printf '  \033[2m○\033[0m  %-18s  \033[0;31m%s\033[0m  (stale)\n' "$op" "$p"
                    ((stale++))
                }
            done
        done
    done < <(_ob_keys OPS)

    printf '\n'
    [[ $stale -eq 0 ]] && _ob_green "✔  All domain paths exist on disk"
    [[ $all_ok -eq 0 || $stale -gt 0 ]] && \
        _ob_yellow "⚠  ${stale} stale path(s). Run '${OB_CLI_NAME} suggest operations' to analyse."
}