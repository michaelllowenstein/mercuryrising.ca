# DERIVATION OF THE DOMAIN MANIFEST

Step 1  cp packages/core/tenants/generic/domain/domain.json \
           packages/core/tenants/{slug}/domain/domain.json

Step 2  Edit tenant.slug, tenant.brand_name, tenant.cli_name

Step 3  Edit config.repos — one entry per repository the team works across

Step 4  Replace operations with real business flows (one interview session with a senior engineer)

Step 5  Replace statuses with real status codes pulled from the database enum

Step 6  Populate products, portals, queues if applicable; leave {} if not

Step 7  Replace generic glossary with team-specific vocabulary

Step 8  Replace generic scan_rules with team-specific compliance rules (or add on top of them)

Step 9  python3 packages/core/scripts/validate_domain.py --tenant {slug}

Step 10 python3 packages/core/scripts/generate_adapters.py --tenant {slug}

Step 11 source packages/cli/src/ob_dispatcher.zsh   # then test: ob where create