#!/usr/bin/env bats
# test_scan_msi.bats — ob_scan_engine against scan fixtures

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)"
    SCAN_HELPER="${REPO_ROOT}/packages/cli/tests/helpers/ob_scan_helper.zsh"
    FIXTURES="${REPO_ROOT}/packages/cli/tests/fixtures/scan_fixtures"
    if [[ ! -f "${REPO_ROOT}/packages/core/generated/msi/scan_rules.zsh" ]]; then
        skip "MSI scan rules not generated yet"
    fi
}

@test "ob_scan_list: exits 0 and outputs rule IDs" {
    run zsh "$SCAN_HELPER" msi ob_scan_list
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ob_scan: hardcoded_secret fires on ViolationService.cs" {
    run zsh "$SCAN_HELPER" msi ob_scan hardcoded_secret "${FIXTURES}/ViolationService.cs"
    [ "$status" -ne 0 ]
}

@test "ob_scan: hardcoded_secret clean on PolicyService.clean.cs" {
    run zsh "$SCAN_HELPER" msi ob_scan hardcoded_secret "${FIXTURES}/PolicyService.clean.cs"
    [ "$status" -eq 0 ]
}

@test "ob_scan: detects violation in TestData.violation.json" {
    run zsh "$SCAN_HELPER" msi ob_scan hardcoded_secret "${FIXTURES}/TestData.violation.json"
    [ "$status" -ne 0 ]
}