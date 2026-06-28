#!/usr/bin/env zsh
# ob_nav_helper.zsh — Zsh subprocess for bats nav tests
# Usage: zsh ob_nav_helper.zsh <tenant> <function> [args...]
# Bats calls this via: run zsh "$NAV_HELPER" generic ob_where create

tenant="${1:?tenant required}"; shift
fn="${1:?function required}";   shift

export OB_TENANT="$tenant"
export OB_NAV_SLUG="${tenant:u}"

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h:h:h}"

source "${REPO_ROOT}/packages/core/generated/${tenant}/nav_maps.zsh"   || exit 1
source "${REPO_ROOT}/packages/core/generated/${tenant}/scan_rules.zsh" 2>/dev/null || true
source "${REPO_ROOT}/packages/cli/src/core/ob_core_display.zsh"        || exit 1
source "${REPO_ROOT}/packages/cli/src/core/ob_core_loader.zsh"         || exit 1
source "${REPO_ROOT}/packages/cli/src/nav/ob_nav_engine.zsh"           || exit 1

"$fn" "$@"