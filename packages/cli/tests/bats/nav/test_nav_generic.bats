#!/usr/bin/env bats
# test_nav_generic.bats — ob_nav_engine against the generic tenant

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)"
    NAV_HELPER="${REPO_ROOT}/packages/cli/tests/helpers/ob_nav_helper.zsh"
}

@test "ob_where: exits 0 for known operation 'bind'" {
    run zsh "$NAV_HELPER" generic ob_where bind
    [ "$status" -eq 0 ]
}

@test "ob_where: output contains controller path" {
    run zsh "$NAV_HELPER" generic ob_where bind
    [ "$status" -eq 0 ]
    [[ "$output" == *"Controller"* ]]
}

@test "ob_where: exits non-zero for unknown operation" {
    run zsh "$NAV_HELPER" generic ob_where __nonexistent__
    [ "$status" -ne 0 ]
}

@test "ob_status: lists all codes when called with no arg" {
    run zsh "$NAV_HELPER" generic ob_status
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ob_explain: exits 0 for 'fnol'" {
    run zsh "$NAV_HELPER" generic ob_explain fnol
    [ "$status" -eq 0 ]
    [[ "$output" == *"FNOL"* ]]
}

@test "ob_explain: exits non-zero for unknown term" {
    run zsh "$NAV_HELPER" generic ob_explain __nosuchterm__
    [ "$status" -ne 0 ]
}

@test "ob_list: exits 0 and includes known operations" {
    run zsh "$NAV_HELPER" generic ob_list ops
    [ "$status" -eq 0 ]
    [[ "$output" == *"bind"* ]]
}

@test "ob_list: exits 0 for rules" {
    run zsh "$NAV_HELPER" generic ob_list rules
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}