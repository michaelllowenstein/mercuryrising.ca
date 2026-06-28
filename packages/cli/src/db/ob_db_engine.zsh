#!/usr/bin/env zsh
# ob_db_engine.zsh — Onboarded DB intelligence engine v1.0.0
# Provides: ob_schema, ob_sql, ob_cluster, ob_policy
# Depends on: ob_core_display.zsh, ob_core_loader.zsh (sourced by dispatcher)
# Data:  ${OB_NAV_SLUG}_SCHEMA, ${OB_NAV_SLUG}_SQL_TEMPLATES, ${OB_NAV_SLUG}_CLUSTERS
#        loaded from packages/core/generated/{tenant}/db_maps.zsh

[[ -n "${_OB_DB_ENGINE_LOADED:-}" ]] && return 0
typeset -g _OB_DB_ENGINE_LOADED=1

# Resolve templates directory from dispatcher path
_OB_TEMPLATES_DIR="${_OB_DISPATCHER_DIR:h:h}/templates"

# ── Private helpers ───────────────────────────────────────────────────────────
_ob_db_copy() {
    if command -v pbcopy &>/dev/null; then
        printf '%s' "$1" | pbcopy
        _ob_dim "  → Copied to clipboard. Paste into Azure Data Studio."
    elif command -v xclip &>/dev/null; then
        printf '%s' "$1" | xclip -selection clipboard
        _ob_dim "  → Copied to clipboard."
    else
        _ob_dim "  → Install pbcopy (macOS) or xclip (Linux) for auto-copy."
    fi
}

_ob_db_exec() {
    local sql="$1"
    local server="${MSI_DB_READONLY_SERVER:-}"
    if [[ -z "$server" ]]; then
        _ob_yellow "  Live execution disabled."
        _ob_dim    "  Set MSI_DB_READONLY_SERVER in ~/.zshrc to enable."
        return 1
    fi
    if ! command -v sqlcmd &>/dev/null; then
        _ob_yellow "  sqlcmd not in PATH. Install: brew install sqlcmd"
        return 1
    fi
    _ob_cyan "  Executing against ${server} ..."
    sqlcmd -S "$server" -d "${MSI_DB_NAME:-MSI}" -G -Q "$sql"
}

# ── ob_schema ─────────────────────────────────────────────────────────────────
ob_schema() {
    local query="${1:l}"
    local schema_arr="${OB_NAV_SLUG}_SCHEMA"

    if [[ -z "$query" ]]; then
        _ob_bold "Cached Schema Profiles — ${OB_CLI_NAME}"
        _ob_sep
        eval "for k in \"\${(ko@)${schema_arr}}\"; do
            local val; eval \"val=\\\"\${${schema_arr}[\$k]}\\\"\"
            local -a cols; cols=(\"\${(@s:|:)val}\")
            local col_count=\$(( \${#cols} - 1 ))
            printf '  \033[0;36m%-52s\033[0m  %d confirmed columns\n' \"\$k\" \"\$col_count\"
        done"
        _ob_sep
        _ob_dim "Usage: ${OB_CLI_NAME} schema <schema.Table>"
        return 0
    fi

    # Find match (exact then substring)
    local matched_key=""
    eval "for k in \"\${(k@)${schema_arr}}\"; do
        [[ \"\${k:l}\" == \"${query}\" ]] && { matched_key=\"\$k\"; break; }
    done"
    [[ -z "$matched_key" ]] && eval "for k in \"\${(k@)${schema_arr}}\"; do
        [[ \"\${k:l}\" == *\"${query}\"* ]] && { matched_key=\"\$k\"; break; }
    done"

    local target="${matched_key:-$1}"
    _ob_bold "SCHEMA: ${target}"
    _ob_sep

    if [[ -n "$matched_key" ]]; then
        local val; eval "val=\"\${${schema_arr}[${matched_key}]}\""
        local -a parts; parts=("${(@s:|:)val}")
        local meta="${parts[1]}"
        local date_confirmed="${meta%%:*}" ticket="${meta##*:}"

        _ob_dim "  Confirmed: ${date_confirmed}  ticket: ${ticket}"
        _ob_dim "  Run live Q0 below to verify before any schema-dependent query."
        printf '\n'

        local col_id=0
        for col_entry in "${parts[@]:1}"; do
            (( col_id++ ))
            local cname="${col_entry%%:*}" rest="${col_entry#*:}"
            local ctype="${rest%%:*}" cnull="${rest##*:}"
            local nlabel; [[ "$cnull" == "0" ]] && nlabel="NOT NULL" || nlabel="NULL   "
            printf "    %3d  %-40s  %-16s  %s\n" "$col_id" "$cname" "$ctype" "$nlabel"
        done
        printf '\n'
    else
        _ob_yellow "  No cached profile for '${target}'."
        _ob_dim    "  Run the Q0 probe below, then add results to domain.json → db_schema."
        printf '\n'
    fi

    local q0_sql="SELECT
    c.column_id,
    c.name          AS ColumnName,
    t.name          AS TypeName,
    c.max_length,
    c.is_nullable
FROM   sys.columns c
JOIN   sys.types   t ON t.user_type_id = c.user_type_id
WHERE  c.object_id = OBJECT_ID(N'${target}')
ORDER  BY c.column_id;"

    _ob_yellow "  Live Q0 probe:"
    printf '\n'
    while IFS= read -r line; do printf "    %s\n" "$line"; done <<< "$q0_sql"
    printf '\n'
    _ob_db_copy "$q0_sql"

    [[ "${2:-}" == "--exec" || "${2:-}" == "-x" ]] && _ob_db_exec "$q0_sql"
    _ob_sep
}

# ── ob_cluster ────────────────────────────────────────────────────────────────
ob_cluster() {
    local input="${(L)*}"
    local clusters_arr="${OB_NAV_SLUG}_CLUSTERS"

    if [[ -z "$input" ]]; then
        _ob_bold "Error Cluster Registry — ${OB_CLI_NAME}"
        _ob_sep
        eval "for k in \"\${(k@)${clusters_arr}}\"; do
            local d; eval \"d=\\\"\${${clusters_arr}[\$k]}\\\"\"
            local code=\"\${d#*|}\" ; code=\"\${code%%|*}\"
            printf '  %-50s  %s\n' \"\$k\" \"\$code\"
        done"
        _ob_sep
        _ob_dim "Usage: ${OB_CLI_NAME} cluster <error message fragment>"
        return 0
    fi

    local matched_key="" matched_data=""
    eval "for k in \"\${(k@)${clusters_arr}}\"; do
        [[ \"\${input}\" == *\"\${(L)k}\"* ]] && { matched_key=\"\$k\"; break; }
    done"

    if [[ -z "$matched_key" ]]; then
        _ob_red "No cluster match for: '${*}'"
        _ob_dim "Run: ${OB_CLI_NAME} cluster  (no args) to browse all known patterns."
        return 1
    fi

    eval "matched_data=\"\${${clusters_arr}[${matched_key}]}\""

    local -a p; p=("${(@s:|:)matched_data}")
    local label="${p[1]}" code="${p[2]}" table="${p[3]}"
    local fix="${p[4]}" tmpl="${p[5]}" check="${p[6]}"

    _ob_bold "CLUSTER MATCH"
    _ob_cyan  "  ${label}"
    _ob_sep
    printf '\n'
    _ob_kv "Cluster:"      "$code"
    _ob_kv "Target table:" "$table"
    _ob_kv "Fix:"          "$fix"
    [[ -n "$check" ]] && { printf '\n'; _ob_yellow "  Variant check:"; _ob_dim "    ${check}"; }
    printf '\n'
    _ob_yellow "  Next step:"
    _ob_dim    "    ${OB_CLI_NAME} sql ${tmpl} <snapshot_id>"
    _ob_sep
}

# ── ob_sql ────────────────────────────────────────────────────────────────────
ob_sql() {
    local key="$1"; shift
    local templates_arr="${OB_NAV_SLUG}_SQL_TEMPLATES"

    if [[ -z "$key" ]]; then
        _ob_bold "SQL Template Library — ${OB_CLI_NAME}"
        _ob_sep
        eval "for k in \"\${(ko@)${templates_arr}}\"; do
            local d; eval \"d=\\\"\${${templates_arr}[\$k]}\\\"\"
            local desc=\"\${d%%|*}\" file=\"\${d##*|}\"
            local marker='○'; [[ -f \"${_OB_TEMPLATES_DIR}/\${file}\" ]] && marker='✔'
            printf '  %s %-44s  %s\n' \"\$marker\" \"\$k\" \"\$desc\"
        done"
        _ob_sep
        _ob_dim "Usage: ${OB_CLI_NAME} sql <key> [arg1 arg2 ...]  [--exec]"
        return 0
    fi

    local tmpl_data; eval "tmpl_data=\"\${${templates_arr}[${key}]}\""
    if [[ -z "$tmpl_data" ]]; then
        _ob_red "Unknown template: '${key}'"
        _ob_dim "Run: ${OB_CLI_NAME} sql  (no args) to list all."
        return 1
    fi

    local desc="${tmpl_data%%|*}" file="${tmpl_data##*|}"
    local tmpl_path="${_OB_TEMPLATES_DIR}/${file}"

    if [[ ! -f "$tmpl_path" ]]; then
        _ob_red "Template file not found: ${tmpl_path}"
        return 1
    fi

    local exec_flag="" sql
    sql=$(cat "$tmpl_path")

    local -a clean_args=()
    for arg in "$@"; do
        [[ "$arg" == "--exec" || "$arg" == "-x" ]] && exec_flag=1 || clean_args+=("$arg")
    done

    # Sequential {{TOKEN}} substitution
    local i=1
    while [[ "$sql" == *"{{"* ]]; do
        local val="${clean_args[$i]:-}"
        [[ -z "$val" ]] && break
        sql="${sql/\{\{*\}\}/${val}}"   # replace first {{TOKEN}} with arg
        # More robust: extract token name then replace
        local tok="${${sql##*\{\{}%%\}\}*}"
        [[ -n "$tok" ]] && sql="${sql//\{\{${tok}\}\}/${val}}"
        (( i++ ))
    done

    _ob_bold "SQL: ${key}"
    _ob_cyan  "  ${desc}"
    _ob_sep
    printf '\n'

    [[ "$sql" == *"{{"* ]] && {
        _ob_yellow "  ⚠ Unfilled tokens — provide positional args after key"
        printf '\n'
    }

    while IFS= read -r line; do printf "    %s\n" "$line"; done <<< "$sql"
    printf '\n'
    _ob_db_copy "$sql"
    [[ -n "$exec_flag" ]] && _ob_db_exec "$sql"
    _ob_sep
}

# ── ob_policy ─────────────────────────────────────────────────────────────────
ob_policy() {
    local prefix="${1:u}" number="$2"

    if [[ -z "$prefix" ]]; then
        _ob_red "Usage: ${OB_CLI_NAME} policy <PREFIX> <NUMBER>"
        _ob_dim "       ${OB_CLI_NAME} policy PWB 1175340"
        _ob_dim "       ${OB_CLI_NAME} policy PWB1175340    (combined)"
        return 1
    fi

    # Accept combined: msi policy PWB1175340
    if [[ -z "$number" && "$prefix" =~ ^([A-Z]+)([0-9]+)$ ]]; then
        number="${match[2]}"; prefix="${match[1]}"
    fi

    [[ -z "$number" ]] && {
        _ob_red "Could not parse number from '${1}'. Use: ${OB_CLI_NAME} policy PWB 1175340"
        return 1
    }

    local sql="-- Policy snapshot lookup: ${prefix}${number}
SELECT
    pt.PolicyTermID, pt.PolicyNumber, pt.PolicyPrefix, pt.TermNumber,
    pts.PolicyTermSnapshotID, pts.IsActivePolicyTermSnapshot,
    pts.PolicyTermSnapshotSequenceNumber, pts.PolicyStatusCode,
    pts.CreatedDate, pts.LastUpdateDate
FROM   policy.PolicyTerm         pt
JOIN   policy.PolicyTermSnapshot pts ON pts.PolicyTermID = pt.PolicyTermID
WHERE  pt.PolicyPrefix = N'${prefix}'
  AND  pt.PolicyNumber = ${number}
ORDER  BY pt.TermNumber ASC, pts.PolicyTermSnapshotID DESC;
-- [!] All IsActivePolicyTermSnapshot = 0 → Cluster C. Run: ${OB_CLI_NAME} cluster 'sequence contains no elements'"

    _ob_bold "POLICY LOOKUP: ${prefix}${number}"
    _ob_sep
    printf '\n'
    while IFS= read -r line; do printf "    %s\n" "$line"; done <<< "$sql"
    printf '\n'
    _ob_db_copy "$sql"

    [[ "${3:-}" == "--exec" || "${3:-}" == "-x" ]] && _ob_db_exec "$sql"
    _ob_sep
}