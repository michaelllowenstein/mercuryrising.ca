#!/usr/bin/env bats
# test_nav_msi.bats — ob_nav_engine against the MSI tenant

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)"
    NAV_HELPER="${REPO_ROOT}/packages/cli/tests/helpers/ob_nav_helper.zsh"
    if [[ ! -f "${REPO_ROOT}/packages/core/generated/msi/nav_maps.zsh" ]]; then
        skip "MSI adapters not generated yet"
    fi
}

@test "ob_where: exits 0 for 'bind'" {
    run zsh "$NAV_HELPER" msi ob_where bind
    [ "$status" -eq 0 ]
}

@test "ob_where: bind output contains controller path" {
    run zsh "$NAV_HELPER" msi ob_where bind
    [ "$status" -eq 0 ]
    [[ "$output" == *"Controller"* ]]
}

@test "ob_status: exits 0 for code 36" {
    run zsh "$NAV_HELPER" msi ob_status 36
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ob_explain: exits 0 for 'fnol'" {
    run zsh "$NAV_HELPER" msi ob_explain fnol
    [ "$status" -eq 0 ]
}

@test "ob_list: includes 'bind' in ops list" {
    run zsh "$NAV_HELPER" msi ob_list ops
    [ "$status" -eq 0 ]
    [[ "$output" == *"bind"* ]]
}