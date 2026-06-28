
#!/usr/bin/env zsh
# ob_scan_helper.zsh — Zsh subprocess for bats scan tests
# Usage: zsh ob_scan_helper.zsh <tenant> <function> [args...]

tenant="${1:?tenant required}"; shift
fn="${1:?function required}";   shift

export OB_TENANT="$tenant"
export OB_NAV_SLUG="${tenant:u}"

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h:h:h}"

source "${REPO_ROOT}/packages/core/generated/${tenant}/nav_maps.zsh"   || exit 1
source "${REPO_ROOT}/packages/core/generated/${tenant}/scan_rules.zsh" || exit 1
source "${REPO_ROOT}/packages/cli/src/core/ob_core_display.zsh"        || exit 1
source "${REPO_ROOT}/packages/cli/src/core/ob_core_loader.zsh"         || exit 1
source "${REPO_ROOT}/packages/cli/src/scan/ob_scan_engine.zsh"         || exit 1

"$fn" "$@"