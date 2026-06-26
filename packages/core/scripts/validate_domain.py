#!/usr/bin/env python3
"""
validate_domain.py — Validate one or all tenant domain.json files against tenant.schema.json.

Usage:
  python3 packages/core/scripts/validate_domain.py --tenant generic
  python3 packages/core/scripts/validate_domain.py --tenant msi
  python3 packages/core/scripts/validate_domain.py --all
  python3 packages/core/scripts/validate_domain.py --all --strict
"""
import sys
import json
import pathlib
import argparse

try:
    import jsonschema
    from jsonschema import validate, ValidationError, SchemaError
except ImportError:
    print("ERROR: jsonschema is required.  Run: pip install jsonschema", file=sys.stderr)
    sys.exit(1)

REPO_ROOT   = pathlib.Path(__file__).resolve().parents[3]
TENANTS_DIR = REPO_ROOT / "packages" / "core" / "tenants"
SCHEMA_PATH = REPO_ROOT / "packages" / "core" / "data" / "tenant.schema.json"


def load_schema() -> dict:
    if not SCHEMA_PATH.exists():
        print(f"ERROR: schema not found: {SCHEMA_PATH}", file=sys.stderr)
        sys.exit(1)
    with open(SCHEMA_PATH, encoding="utf-8") as fh:
        return json.load(fh)


def find_domain(tenant: str) -> pathlib.Path:
    """Return the domain.json path for a tenant (flat layout only)."""
    path = TENANTS_DIR / tenant / "domain.json"
    if path.exists():
        return path
    print(f"ERROR: domain.json not found for tenant '{tenant}'", file=sys.stderr)
    print(f"  Expected: {path}", file=sys.stderr)
    sys.exit(1)


def load_domain(path: pathlib.Path) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in {path}", file=sys.stderr)
        print(f"  {exc}", file=sys.stderr)
        sys.exit(1)


def _cross_validate(domain: dict, tenant: str) -> list[str]:
    """
    Domain-level consistency checks that JSON Schema cannot express.
    Returns a list of warning strings (non-fatal unless --strict).
    """
    warnings = []
    ops   = domain.get("operations", {})
    gloss = domain.get("glossary", {})
    rules = domain.get("scan_rules", {})
    slug  = domain.get("tenant", {}).get("slug", tenant)

    if slug != tenant:
        warnings.append(
            f"tenant.slug '{slug}' does not match directory name '{tenant}'"
        )

    # Glossary see_also references must exist as glossary keys
    for term, entry in gloss.items():
        for ref in entry.get("see_also", []):
            if ref not in gloss:
                warnings.append(
                    f"glossary[{term}].see_also references '{ref}' which is not in glossary"
                )

    # scan_rules patterns should compile as valid regex
    import re
    for rule_id, rule in rules.items():
        pattern = rule.get("pattern", "")
        try:
            re.compile(pattern)
        except re.error as exc:
            warnings.append(f"scan_rules[{rule_id}].pattern is invalid regex: {exc}")

    # qe_tests keys should correspond to known operations (advisory only)
    for op_key in domain.get("qe_tests", {}):
        if op_key not in ops:
            warnings.append(
                f"qe_tests[{op_key}] has no matching entry in operations"
            )

    # glossary_xrefs keys should correspond to known glossary terms
    for term in domain.get("glossary_xrefs", {}):
        if term not in gloss:
            warnings.append(
                f"glossary_xrefs[{term}] has no matching entry in glossary"
            )

    # status_triggers keys should correspond to known status codes
    statuses = domain.get("statuses", {})
    for code in domain.get("status_triggers", {}):
        if str(code) not in statuses:
            warnings.append(
                f"status_triggers[{code}] has no matching entry in statuses"
            )

    return warnings


def validate_tenant(tenant: str, schema: dict, strict: bool = False) -> bool:
    """Validate one tenant. Returns True if passed (warnings are ok unless strict)."""
    path   = find_domain(tenant)
    domain = load_domain(path)

    rel = path.relative_to(REPO_ROOT)
    print(f"[validate] {tenant}  ({rel})")

    # JSON Schema validation
    try:
        validate(instance=domain, schema=schema)
    except ValidationError as exc:
        print(f"  FAIL  schema error at {' > '.join(str(p) for p in exc.absolute_path)}")
        print(f"        {exc.message}")
        return False
    except SchemaError as exc:
        print(f"  FAIL  the schema itself is invalid: {exc.message}", file=sys.stderr)
        sys.exit(2)

    # Cross-validation checks
    warnings = _cross_validate(domain, tenant)
    for w in warnings:
        level = "FAIL " if strict else "WARN "
        print(f"  {level} {w}")

    if strict and warnings:
        return False

    ops_count   = len(domain.get("operations",  {}))
    gloss_count = len(domain.get("glossary",    {}))
    rules_count = len(domain.get("scan_rules",  {}))
    print(f"  ok    {ops_count} operations  {gloss_count} glossary  {rules_count} scan rules")
    return True


def discover_tenants() -> list[str]:
    if not TENANTS_DIR.exists():
        return []
    return sorted(
        d.name for d in TENANTS_DIR.iterdir()
        if d.is_dir() and (d / "domain.json").exists()
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Onboarded domain validator")
    grp = parser.add_mutually_exclusive_group(required=True)
    grp.add_argument("--tenant", metavar="SLUG", help="Validate a single tenant")
    grp.add_argument("--all",    action="store_true", help="Validate all tenants")
    parser.add_argument("--strict", action="store_true",
                        help="Treat cross-validation warnings as failures")
    args = parser.parse_args()

    schema  = load_schema()
    tenants = [args.tenant] if args.tenant else discover_tenants()

    if not tenants:
        print(f"ERROR: no tenants found under {TENANTS_DIR}", file=sys.stderr)
        sys.exit(1)

    results = {t: validate_tenant(t, schema, strict=args.strict) for t in tenants}

    failed = [t for t, ok in results.items() if not ok]
    if failed:
        print(f"\nFAILED: {', '.join(failed)}")
        sys.exit(1)

    print(f"\nAll {len(results)} tenant(s) valid.")


if __name__ == "__main__":
    main()