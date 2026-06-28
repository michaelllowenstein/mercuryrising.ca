#!/usr/bin/env python3
"""
generate_adapters.py — Onboarded v1.1.0 Adapter Generator

Reads a tenant domain.json and emits FIVE generated files:
  packages/core/generated/<tenant>/nav_maps.zsh      — Zsh nav hash maps
  packages/core/generated/<tenant>/scan_rules.zsh    — Zsh scan rule arrays
  packages/core/generated/<tenant>/nav_maps.ps1      — PowerShell nav hash tables
  packages/core/generated/<tenant>/scan_rules.ps1    — PowerShell scan rule hash tables
  packages/shared/src/lib/tenants/<tenant>.ts         — TypeScript snapshot (NEW in v1.1.0)

Usage:
    python3 packages/core/scripts/generate_adapters.py --tenant msi
    python3 packages/core/scripts/generate_adapters.py --tenant generic
    python3 packages/core/scripts/generate_adapters.py --all
    python3 packages/core/scripts/generate_adapters.py --all --ts-only

Key design decisions:
    1. Pattern values are base64-encoded in the generated arrays to eliminate
       the pipe-collision risk when a regex contains literal | characters.
       The scan engines decode at runtime using: base64 -d (POSIX) or
       [System.Convert]::FromBase64String() (PowerShell).

    2. This script is the only place that knows the internal array value
       format. Shell engines must use _ob_scan_field() to extract fields.
       Never parse the raw value string directly in engine code.

    3. Empty arrays (repos: [], exclude: []) are emitted as empty string
       fields in the value, not omitted. This keeps field position stable.

    4. TypeScript snapshots are emitted to packages/shared/src/lib/tenants/
       as a TENANT_DOMAIN const — imported at Angular build time. They are
       gitignored and always regenerated; never hand-edit them.

Exit codes:
    0 — success
    1 — domain validation errors
    2 — input file not found
"""

import argparse
import base64
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Path resolution — works from any working directory ────────────────────────
SCRIPT_DIR   = Path(__file__).resolve().parent          # packages/core/scripts/
CORE_DIR     = SCRIPT_DIR.parent                        # packages/core/
REPO_ROOT    = CORE_DIR.parent.parent                   # onboarded/ (contains nx.json)
TENANTS_DIR  = CORE_DIR / "tenants"
GENERATED    = CORE_DIR / "generated"
SHARED_TENANTS = REPO_ROOT / "packages" / "shared" / "src" / "lib" / "tenants"

# ── Field separator ───────────────────────────────────────────────────────────
SEP = "|"

# ── Minimal structural validator (no external deps) ───────────────────────────
REQUIRED_TOP     = ["version", "tenant", "config", "operations", "statuses", "glossary", "scan_rules"]
VALID_SEVERITIES = {"critical", "error", "warning", "info"}
VALID_CATEGORIES = {"security", "convention", "architecture", "dependency", "observability"}


def validate(domain: dict) -> list[str]:
    errors = []
    for key in REQUIRED_TOP:
        if key not in domain:
            errors.append(f"Missing top-level key: '{key}'")

    tenant = domain.get("tenant", {})
    for field in ["slug", "brand_name", "cli_name"]:
        if not tenant.get(field):
            errors.append(f"tenant.{field}: required")

    for rule_id, rule in domain.get("scan_rules", {}).items():
        prefix = f"scan_rules.{rule_id}"
        for field in ["label", "pattern", "severity", "scope"]:
            if field not in rule:
                errors.append(f"{prefix}: missing '{field}'")
        sev = rule.get("severity")
        if sev and sev not in VALID_SEVERITIES:
            errors.append(f"{prefix}: invalid severity '{sev}'")
        cat = rule.get("category")
        if cat and cat not in VALID_CATEGORIES:
            errors.append(f"{prefix}: invalid category '{cat}'")
        scope = rule.get("scope")
        if isinstance(scope, list) and len(scope) == 0:
            errors.append(f"{prefix}: scope must have at least one glob")

    version = domain.get("version", "")
    parts = version.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        errors.append(f"version: '{version}' is not valid semver (expected x.y.z)")

    return errors


# ── Helpers ───────────────────────────────────────────────────────────────────
def b64(s: str) -> str:
    return base64.b64encode(s.encode()).decode()


def pipe_join(items: list) -> str:
    return ";".join(str(i) for i in items)


def zsh_safe(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")


def ps1_safe(s: str) -> str:
    return s.replace("'", "''")


def ts_safe(s: str) -> str:
    return s.replace("\\", "\\\\").replace("`", "\\`").replace("$", "\\$").replace("'", "\\'")


# ── Zsh nav maps ──────────────────────────────────────────────────────────────
def emit_nav_maps_zsh(domain: dict, tenant: str) -> str:
    meta  = domain.get("tenant", {})
    ts    = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    slug  = tenant.upper()
    lines = []

    lines += [
        f"# ─────────────────────────────────────────────────────────────────────────",
        f"# {slug}_nav_maps.zsh  —  AUTO-GENERATED by packages/core/scripts/generate_adapters.py",
        f"# Tenant: {meta.get('brand_name', tenant)}  v{domain.get('version', '?')}",
        f"# Generated: {ts}",
        f"# DO NOT EDIT — edit packages/core/tenants/{tenant}/domain/domain.json instead",
        f"# ─────────────────────────────────────────────────────────────────────────",
        "",
        f"# ── Tenant metadata ──────────────────────────────────────────────────────",
        f'export OB_BRAND_NAME="{zsh_safe(meta.get("brand_name", tenant))}"',
        f'export OB_CLI_NAME="{zsh_safe(meta.get("cli_name", "onboarded"))}"',
        f'export OB_TENANT_SLUG="{zsh_safe(meta.get("slug", tenant))}"',
        "",
    ]

    # Repo roots
    lines += [
        "# ── Repo roots ──────────────────────────────────────────────────────────────",
        f"typeset -gA {slug}_REPOS",
    ]
    for repo_id, repo_cfg in domain.get("config", {}).get("repos", {}).items():
        env     = repo_cfg.get("env", "")
        default = repo_cfg.get("default", repo_id)
        lines.append(
            f'{slug}_REPOS["{zsh_safe(repo_id)}"]="${{{env}:-${{{slug}_ROOT:-$OB_ROOT}}/{zsh_safe(default)}}}"'
        )
    lines.append("")

    # Operations — value format: label||controllers||services||queues||js
    lines += [
        "# ── Operations ──────────────────────────────────────────────────────────────",
        f"typeset -gA {slug}_OPS",
    ]
    for op_id, op in domain.get("operations", {}).items():
        controllers = pipe_join(op.get("controllers", []))
        services    = pipe_join(op.get("services", []))
        queues      = pipe_join(op.get("queues", []))
        js          = pipe_join(op.get("js", []))
        label       = op.get("label", op_id)
        value       = f"{label}||{controllers}||{services}||{queues}||{js}"
        lines.append(f'{slug}_OPS["{zsh_safe(op_id)}"]"{zsh_safe(value)}"')
        # Fix: correct assignment syntax
        lines[-1] = f'{slug}_OPS["{zsh_safe(op_id)}"]"{zsh_safe(value)}"'
        lines[-1] = f'{slug}_OPS["{zsh_safe(op_id)}"]=' + f'"{zsh_safe(value)}"'
    lines.append("")

    # Statuses
    lines += [
        "# ── Statuses ─────────────────────────────────────────────────────────────────",
        f"typeset -gA {slug}_STATUS",
    ]
    for code, desc in domain.get("statuses", {}).items():
        lines.append(f'{slug}_STATUS["{zsh_safe(code)}"]=' + f'"{zsh_safe(desc)}"')
    lines.append("")

    # Products (optional)
    # Format: label|code|controllers_semi|gen3_semi|js_semi|webjobs_semi
    if domain.get("products"):
        lines += [
            "# ── Products ─────────────────────────────────────────────────────────────────",
            f"typeset -gA {slug}_PRODUCTS",
        ]
        for prod_id, prod in domain.get("products", {}).items():
            label = prod.get("label", prod_id)
            code  = str(prod.get("code", ""))
            ctrl  = ";".join(prod.get("controllers", []))
            gen3  = ";".join(prod.get("gen3",        []))
            js    = ";".join(prod.get("js",          []))
            wj    = ";".join(prod.get("webjobs",     []))
            value = f"{label}|{code}|{ctrl}|{gen3}|{js}|{wj}"
            lines.append(f'{slug}_PRODUCTS["{zsh_safe(prod_id)}"]=' + f'"{zsh_safe(value)}"')
        lines.append("")

    # Portals — Format: name|path|products_semi
    if domain.get("portals"):
        lines += [
            "# ── Portals ──────────────────────────────────────────────────────────────────",
            f"typeset -gA {slug}_PORTALS",
        ]
        for portal_id, portal in domain.get("portals", {}).items():
            name  = zsh_safe(portal.get("name", portal_id))
            path  = zsh_safe(portal.get("path", ""))
            prods = ";".join(portal.get("products", []))
            lines.append(f'{slug}_PORTALS["{zsh_safe(portal_id)}"]=' + f'"{name}|{path}|{prods}"')
        lines.append("")

    # Queues — Format: label|consumer|webjobs|description
    if domain.get("queues"):
        lines += [
            "# ── Queues ───────────────────────────────────────────────────────────────────",
            f"typeset -gA {slug}_QUEUES",
        ]
        for q_id, q in domain.get("queues", {}).items():
            label    = zsh_safe(q.get("label",       q_id))
            consumer = zsh_safe(q.get("consumer",    ""))
            webjobs  = zsh_safe(q.get("webjobs",     ""))   # string, not array
            desc     = zsh_safe(q.get("description", ""))
            lines.append(
                f'{slug}_QUEUES["{zsh_safe(q_id)}"]=' + f'"{label}|{consumer}|{webjobs}|{desc}"'
            )
        lines.append("")

    # Glossary (optional)
    if domain.get("glossary"):
        lines += [
            "# ── Glossary ─────────────────────────────────────────────────────────────────",
            f"typeset -gA {slug}_GLOSSARY",
        ]
        for term_id, term in domain.get("glossary", {}).items():
            label      = term.get("label", term_id)
            definition = term.get("definition", "")
            see_also   = ";".join(term.get("see_also", []))
            value      = f"{label}|{definition}|{see_also}"
            lines.append(f'{slug}_GLOSSARY["{zsh_safe(term_id)}"]=' + f'"{zsh_safe(value)}"')
        lines.append("")

    return "\n".join(lines)


# ── Zsh scan rules ────────────────────────────────────────────────────────────
def emit_scan_rules_zsh(domain: dict, tenant: str) -> str:
    meta  = domain.get("tenant", {})
    ts    = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    slug  = tenant.upper()
    lines = []

    lines += [
        f"# ─────────────────────────────────────────────────────────────────────────",
        f"# {slug}_scan_rules.zsh  —  AUTO-GENERATED by packages/core/scripts/generate_adapters.py",
        f"# Tenant: {meta.get('brand_name', tenant)}  v{domain.get('version', '?')}",
        f"# Generated: {ts}",
        f"# Value format: severity|category|scope|repos|excludes|pattern_b64|reference|fix_hint|label",
        f"# pattern_b64: base64-encoded ERE — eliminates pipe-collision risk",
        f"# DO NOT EDIT — edit packages/core/tenants/{tenant}/domain/domain.json instead",
        f"# ─────────────────────────────────────────────────────────────────────────",
        "",
        f"typeset -gA {slug}_SCAN_RULES",
        "",
    ]

    by_severity: dict[str, list] = {}
    by_category: dict[str, list] = {}

    for rule_id, rule in domain.get("scan_rules", {}).items():
        severity    = rule.get("severity", "warning")
        category    = rule.get("category", "convention")
        scope       = ";".join(rule.get("scope", []))
        repos       = ";".join(rule.get("repos", []))
        excludes    = ";".join(rule.get("exclude", []))
        pattern_b64 = b64(rule.get("pattern", ""))
        reference   = rule.get("reference", "")
        fix_hint = rule.get("fixHint", rule.get("fix_hint", ""))
        label       = rule.get("label", rule_id)

        value = f"{severity}|{category}|{scope}|{repos}|{excludes}|{pattern_b64}|{zsh_safe(reference)}|{zsh_safe(fix_hint)}|{zsh_safe(label)}"
        lines.append(f'{slug}_SCAN_RULES["{rule_id}"]="{value}"')

        by_severity.setdefault(severity, []).append(rule_id)
        by_category.setdefault(category, []).append(rule_id)

    lines += [
        "",
        f"typeset -gA {slug}_SCAN_BY_SEVERITY",
    ]
    for sev, rule_ids in sorted(by_severity.items()):
        lines.append(f'{slug}_SCAN_BY_SEVERITY["{sev}"]="{";".join(rule_ids)}"')

    lines += [
        "",
        f"typeset -gA {slug}_SCAN_BY_CATEGORY",
    ]
    for cat, rule_ids in sorted(by_category.items()):
        lines.append(f'{slug}_SCAN_BY_CATEGORY["{cat}"]="{";".join(rule_ids)}"')

    lines.append("")
    return "\n".join(lines)


# ── PowerShell nav maps ───────────────────────────────────────────────────────
def emit_nav_maps_ps1(domain: dict, tenant: str) -> str:
    meta  = domain.get("tenant", {})
    ts    = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    slug  = tenant.upper()
    lines = []

    lines += [
        f"# ─────────────────────────────────────────────────────────────────────────",
        f"# {slug}_nav_maps.ps1  —  AUTO-GENERATED by packages/core/scripts/generate_adapters.py",
        f"# Tenant: {meta.get('brand_name', tenant)}  v{domain.get('version', '?')}",
        f"# Generated: {ts}",
        f"# DO NOT EDIT — edit packages/core/tenants/{tenant}/domain/domain.json instead",
        f"# ─────────────────────────────────────────────────────────────────────────",
        "",
        f'$env:OB_BRAND_NAME  = \'{ps1_safe(meta.get("brand_name", tenant))}\'',
        f'$env:OB_CLI_NAME    = \'{ps1_safe(meta.get("cli_name", "onboarded"))}\'',
        f'$env:OB_TENANT_SLUG = \'{ps1_safe(meta.get("slug", tenant))}\'',
        "",
        f"$global:{slug}_REPOS = @{{}}",
    ]

    for repo_id, repo_cfg in domain.get("config", {}).get("repos", {}).items():
        env     = repo_cfg.get("env", "")
        default = repo_cfg.get("default", repo_id)
        lines.append(
            f"$global:{slug}_REPOS['{ps1_safe(repo_id)}'] = "
            f"if ($env:{env}) {{ $env:{env} }} "
            f"else {{ Join-Path ($env:{slug}_ROOT ?? $env:OB_ROOT ?? $HOME) '{ps1_safe(default)}' }}"
        )

    lines += ["", f"$global:{slug}_OPS = @{{}}"]
    for op_id, op in domain.get("operations", {}).items():
        controllers = pipe_join(op.get("controllers", []))
        services    = pipe_join(op.get("services", []))
        queues      = pipe_join(op.get("queues", []))
        js          = pipe_join(op.get("js", []))
        label       = op.get("label", op_id)
        value       = f"{label}||{controllers}||{services}||{queues}||{js}"
        lines.append(f"$global:{slug}_OPS['{ps1_safe(op_id)}'] = '{ps1_safe(value)}'")

    lines += ["", f"$global:{slug}_STATUS = @{{}}"]
    for code, desc in domain.get("statuses", {}).items():
        lines.append(f"$global:{slug}_STATUS['{ps1_safe(code)}'] = '{ps1_safe(desc)}'")

    if domain.get("products"):
        lines += ["", f"$global:{slug}_PRODUCTS = @{{}}"]
        for prod_id, prod in domain.get("products", {}).items():
            label = prod.get("label", prod_id)
            code  = str(prod.get("code", ""))
            ctrl  = ";".join(prod.get("controllers", []))
            gen3  = ";".join(prod.get("gen3",        []))
            js    = ";".join(prod.get("js",          []))
            wj    = ";".join(prod.get("webjobs",     []))
            value = f"{label}|{code}|{ctrl}|{gen3}|{js}|{wj}"
            lines.append(f"$global:{slug}_PRODUCTS['{ps1_safe(prod_id)}'] = '{ps1_safe(value)}'")

    if domain.get("portals"):
        lines += ["", f"$global:{slug}_PORTALS = @{{}}"]
        for portal_id, portal in domain.get("portals", {}).items():
            name  = ps1_safe(portal.get("name", portal_id))
            path  = ps1_safe(portal.get("path", ""))
            prods = ";".join(portal.get("products", []))
            value = f"{name}|{path}|{prods}"
            lines.append(f"$global:{slug}_PORTALS['{ps1_safe(portal_id)}'] = '{ps1_safe(value)}'")

    if domain.get("queues"):
        lines += ["", f"$global:{slug}_QUEUES = @{{}}"]
        for q_id, q in domain.get("queues", {}).items():
            label    = ps1_safe(q.get("label",       q_id))
            consumer = ps1_safe(q.get("consumer",    ""))
            webjobs  = ps1_safe(q.get("webjobs",     ""))   # string, not array
            desc     = ps1_safe(q.get("description", ""))
            value    = f"{label}|{consumer}|{webjobs}|{desc}"
            lines.append(f"$global:{slug}_QUEUES['{ps1_safe(q_id)}'] = '{ps1_safe(value)}'")

    if domain.get("glossary"):
        lines += ["", f"$global:{slug}_GLOSSARY = @{{}}"]
        for term_id, term in domain.get("glossary", {}).items():
            label      = term.get("label", term_id)
            definition = term.get("definition", "")
            see_also   = ";".join(term.get("see_also", []))
            value      = f"{label}|{definition}|{see_also}"
            lines.append(f"$global:{slug}_GLOSSARY['{ps1_safe(term_id)}'] = '{ps1_safe(value)}'")

    lines.append("")
    return "\n".join(lines)


# ── PowerShell scan rules ─────────────────────────────────────────────────────
def emit_scan_rules_ps1(domain: dict, tenant: str) -> str:
    meta  = domain.get("tenant", {})
    ts    = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    slug  = tenant.upper()
    lines = []

    lines += [
        f"# ─────────────────────────────────────────────────────────────────────────",
        f"# {slug}_scan_rules.ps1  —  AUTO-GENERATED by packages/core/scripts/generate_adapters.py",
        f"# Tenant: {meta.get('brand_name', tenant)}  v{domain.get('version', '?')}",
        f"# Generated: {ts}",
        f"# pattern_b64: decode with [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(...))",
        f"# DO NOT EDIT — edit packages/core/tenants/{tenant}/domain/domain.json instead",
        f"# ─────────────────────────────────────────────────────────────────────────",
        "",
        f"$global:{slug}_SCAN_RULES      = @{{}}",
        f"$global:{slug}_SCAN_BY_SEVERITY = @{{}}",
        f"$global:{slug}_SCAN_BY_CATEGORY = @{{}}",
        "",
    ]

    by_severity: dict[str, list] = {}
    by_category: dict[str, list] = {}

    for rule_id, rule in domain.get("scan_rules", {}).items():
        severity    = rule.get("severity", "warning")
        category    = rule.get("category", "convention")
        scope       = ";".join(rule.get("scope", []))
        repos       = ";".join(rule.get("repos", []))
        excludes    = ";".join(rule.get("exclude", []))
        pattern_b64 = b64(rule.get("pattern", ""))
        reference   = rule.get("reference", "")
        fix_hint    = rule.get("fix_hint", "")
        label       = rule.get("label", rule_id)

        value = f"{severity}|{category}|{scope}|{repos}|{excludes}|{pattern_b64}|{ps1_safe(reference)}|{ps1_safe(fix_hint)}|{ps1_safe(label)}"
        lines.append(f"$global:{slug}_SCAN_RULES['{ps1_safe(rule_id)}'] = '{ps1_safe(value)}'")

        by_severity.setdefault(severity, []).append(rule_id)
        by_category.setdefault(category, []).append(rule_id)

    lines.append("")
    for sev, rule_ids in sorted(by_severity.items()):
        lines.append(f"$global:{slug}_SCAN_BY_SEVERITY['{sev}'] = '{';'.join(rule_ids)}'")

    lines.append("")
    for cat, rule_ids in sorted(by_category.items()):
        lines.append(f"$global:{slug}_SCAN_BY_CATEGORY['{cat}'] = '{';'.join(rule_ids)}'")

    lines.append("")
    return "\n".join(lines)


# ── TypeScript snapshot (NEW in v1.1.0) ───────────────────────────────────────
def emit_tenant_ts(domain: dict, tenant: str) -> str:
    ts   = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    meta = domain.get("tenant", {})

    # Camel-case the keys from domain for the TenantDomain interface
    def camel(s: str) -> str:
        parts = s.split("_")
        return parts[0] + "".join(p.capitalize() for p in parts[1:])

    # Serialize as compact JSON embedded in TS
    domain_ts = json.dumps(domain, ensure_ascii=False, indent=2)

    return f"""// AUTO-GENERATED by packages/core/scripts/generate_adapters.py
// Tenant: {meta.get('brand_name', tenant)}  v{domain.get('version', '?')}
// Generated: {ts}
// DO NOT EDIT — edit packages/core/tenants/{tenant}/domain/domain.json instead

import type {{ TenantDomain }} from '../types/tenant.types';

export const TENANT_DOMAIN: TenantDomain = {domain_ts} as unknown as TenantDomain;
"""

def emit_db_maps_zsh(domain: dict, tenant: str) -> str:
    """Emit DB intelligence maps: SCHEMA, SQL_TEMPLATES, CLUSTERS."""
    slug = domain["tenant"]["slug"]
    S    = slug.upper()
    ts   = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    L    = [
        f"# db_maps.zsh — AUTO-GENERATED — do not edit directly",
        f"# Tenant: {slug}   Generated: {ts}",
        "",
    ]

    # ── DB_SCHEMA ─────────────────────────────────────────────────────────────
    # Value format: "confirmed_date:ticket|col:type:nullable|col:type:nullable|..."
    if domain.get("db_schema"):
        L += [f"typeset -gA {S}_SCHEMA", f"{S}_SCHEMA=("]
        for table, tdata in domain["db_schema"].items():
            col_parts = "|".join(
                f"{c['name']}:{c['type']}:{'1' if c['nullable'] else '0'}"
                for c in tdata.get("columns", [])
            )
            meta = f"{tdata.get('confirmed_date','')}:{tdata.get('confirmed_ticket','')}"
            L.append(f'  [{zsh_safe(table)}]="{meta}|{col_parts}"')
        L += [")", ""]

    # ── SQL_TEMPLATES ─────────────────────────────────────────────────────────
    # Value format: "description|file.sql"
    if domain.get("sql_templates"):
        L += [f"typeset -gA {S}_SQL_TEMPLATES", f"{S}_SQL_TEMPLATES=("]
        for key, t in domain["sql_templates"].items():
            desc = zsh_safe(t.get("description", ""))
            file = zsh_safe(t.get("file", ""))
            L.append(f'  [{zsh_safe(key)}]="{desc}|{file}"')
        L += [")", ""]

    # ── CLUSTERS ──────────────────────────────────────────────────────────────
    # Value format: "label|code|target_table|fix_mechanism|template_key|variant_check"
    if domain.get("clusters"):
        L += [f"typeset -gA {S}_CLUSTERS", f"{S}_CLUSTERS=("]
        for pattern, c in domain["clusters"].items():
            val = "|".join(zsh_safe(c.get(f, "")) for f in
                           ["label","code","target_table","fix_mechanism",
                            "template_key","variant_check"])
            L.append(f'  [{zsh_safe(pattern)}]="{val}"')
        L += [")", ""]

    return "\n".join(L) if len(L) > 3 else ""

# ── Main generation logic ─────────────────────────────────────────────────────
def generate_tenant(tenant: str, ts_only: bool = False, dry_run: bool = False) -> int:
    domain_path = TENANTS_DIR / tenant / "domain.json"
    if not domain_path.exists():
        domain_path = TENANTS_DIR / tenant / "domain" / "domain.json"
    if not domain_path.exists():
        print(f"ERROR: domain.json not found for tenant '{tenant}'", file=sys.stderr)
        print(f"  Checked: {TENANTS_DIR / tenant / 'domain.json'}", file=sys.stderr)
        return 2

    with open(domain_path, encoding="utf-8") as f:
        domain = json.load(f)

    errors = validate(domain)
    if errors:
        print(f"Validation FAILED for tenant '{tenant}' ({len(errors)} error(s)):")
        for e in errors:
            print(f"  ✗  {e}")
        return 1

    files: dict[Path, str] = {}

    if not ts_only:
        out_dir = GENERATED / tenant
        out_dir.mkdir(parents=True, exist_ok=True)
        files[out_dir / "nav_maps.zsh"]   = emit_nav_maps_zsh(domain, tenant)
        files[out_dir / "scan_rules.zsh"] = emit_scan_rules_zsh(domain, tenant)
        files[out_dir / "nav_maps.ps1"]   = emit_nav_maps_ps1(domain, tenant)
        files[out_dir / "scan_rules.ps1"] = emit_scan_rules_ps1(domain, tenant)

    # Always emit TypeScript snapshot
    SHARED_TENANTS.mkdir(parents=True, exist_ok=True)
    files[SHARED_TENANTS / f"{tenant}.ts"] = emit_tenant_ts(domain, tenant)

    if dry_run:
        print(f"[dry-run] Would write {len(files)} files for tenant '{tenant}':")
        for p in files:
            print(f"  {p.relative_to(REPO_ROOT)}")
        return 0

    for path, content in files.items():
        path.write_text(content, encoding="utf-8")
        print(f"  wrote  {path.relative_to(REPO_ROOT)}")

    db_maps = emit_db_maps_zsh(domain, tenant)
    if db_maps:
        files[out_dir / "db_maps.zsh"] = db_maps

    brand = domain.get("tenant", {}).get("brand_name", tenant)
    ops   = len(domain.get("operations", {}))
    rules = len(domain.get("scan_rules", {}))
    print(f"  ✔  {brand} v{domain.get('version', '?')} — {ops} ops, {rules} scan rules")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Onboarded adapter generator v1.1.0")
    group  = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--tenant", help="Tenant slug (e.g. msi, generic)")
    group.add_argument("--all",    action="store_true", help="Generate all tenants")
    parser.add_argument("--ts-only",  action="store_true", help="Emit only TypeScript snapshots (skip zsh/ps1)")
    parser.add_argument("--dry-run",  action="store_true", help="Show what would be written without writing")
    args = parser.parse_args()

    if args.all:
        tenants = sorted(
            d.name for d in TENANTS_DIR.iterdir()
            if d.is_dir() and (
                (d / "domain.json").exists() or
                (d / "domain" / "domain.json").exists()
            )
        )
        if not tenants:
            print("No tenants found in packages/core/tenants/", file=sys.stderr)
            return 2
        rc = 0
        for t in tenants:
            print(f"\nGenerating tenant: {t}")
            rc = max(rc, generate_tenant(t, ts_only=args.ts_only, dry_run=args.dry_run))
        return rc
    else:
        return generate_tenant(args.tenant, ts_only=args.ts_only, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())