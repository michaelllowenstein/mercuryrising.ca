# ─────────────────────────────────────────────────────────────────────────────
# justfile — msi-nav ↔ onboarded swap harness + PR gate runner
# https://github.com/casey/just   (install: brew install just)
#
# WHAT IS .bats?
# ──────────────
# .bats files are test scripts written in the Bash Automated Testing System
# (bats-core). Each @test block is an independent test case. bats runs them
# in isolation — each test gets a clean subshell — and reports pass/fail in
# TAP (Test Anything Protocol) format.
#
# The anatomy of a bats test:
#
#   @test "msi where bind: exits 0" {
#       run ob_where bind          # `run` captures stdout, stderr, exit code
#       [ "$status" -eq 0 ]        # assert exit code
#       [[ "$output" == *"BasePolicyController"* ]]   # assert output content
#   }
#
# Key bats variables (set by `run`):
#   $status  — exit code of the last `run` command
#   $output  — combined stdout+stderr of the last `run` command
#   $lines   — $output split into an array by newline
#
# Why bats for shell CLI tests?
#   Shell functions cannot be tested with Jest or pytest because they live in
#   the shell's runtime, not in a process with a stable stdin/stdout. bats is
#   the standard tool for this: it sources your shell files and asserts on
#   the output and exit codes of your functions, exactly as a user would
#   experience them. The `setup()` function runs before each test — it sources
#   the adapters and engine files so each test gets a clean, fully-loaded
#   engine without carrying state from previous tests.
#
# Our three bats suites:
#   test_nav_generic.bats  — engine correctness against the 10-op generic tenant
#   test_nav_msi.bats      — engine correctness against the full MSI domain
#   test_scan_msi.bats     — scan engine field extraction, rule loading, b64 decode
#
# ─────────────────────────────────────────────────────────────────────────────

# ── Configurable paths ────────────────────────────────────────────────────────
MSI_NAV_DIR   := env_var_or_default("MSI_NAV_DIR",   home_directory() + "/msi-nav")
ONBOARDED_DIR := env_var_or_default("ONBOARDED_DIR", home_directory() + "/workspaces/miloseng/onboarded")
OB_TENANT     := env_var_or_default("OB_TENANT",     "msi")
SNAPSHOT_FILE := ONBOARDED_DIR + "/.msi-nav-snapshot.sha"
BATS          := env_var_or_default("BATS", `which bats 2>/dev/null || echo bats`)

# ── Derived paths ─────────────────────────────────────────────────────────────
OB_GENERATED  := ONBOARDED_DIR + "/packages/core/generated/" + OB_TENANT
OB_DISPATCHER := ONBOARDED_DIR + "/packages/cli/src/ob_dispatcher.zsh"
OB_VALIDATE   := ONBOARDED_DIR + "/packages/core/scripts/validate_domain.py"
OB_GENERATE   := ONBOARDED_DIR + "/packages/core/scripts/generate_adapters.py"

# ── Shared zsh source block used by every CLI invocation ─────────────────────
# Written as a variable so it's maintained in one place.
OB_SOURCE_BLOCK := 'export OB_TENANT=' + OB_TENANT + ' OB_NAV_SLUG=' + uppercase(OB_TENANT) + '; \
    source "' + ONBOARDED_DIR + '/packages/core/generated/' + OB_TENANT + '/nav_maps.zsh"; \
    source "' + ONBOARDED_DIR + '/packages/core/generated/' + OB_TENANT + '/scan_rules.zsh"; \
    source "' + ONBOARDED_DIR + '/packages/cli/src/core/ob_core_display.zsh"; \
    source "' + ONBOARDED_DIR + '/packages/cli/src/core/ob_core_loader.zsh"; \
    source "' + ONBOARDED_DIR + '/packages/cli/src/nav/ob_nav_engine.zsh"; \
    source "' + ONBOARDED_DIR + '/packages/cli/src/scan/ob_scan_engine.zsh"; \
    source "' + ONBOARDED_DIR + '/packages/cli/src/ob_dispatcher.zsh" 2>/dev/null'

# ─────────────────────────────────────────────────────────────────────────────
default:
    @just --list --unsorted

# ─────────────────────────────────────────────────────────────────────────────
# STATUS
# ─────────────────────────────────────────────────────────────────────────────

status:
    @echo ""
    @echo "  ── msi-nav (stable) ──────────────────────────────────────────────"
    @echo "  Path:   {{MSI_NAV_DIR}}"
    @if [ -d "{{MSI_NAV_DIR}}/.git" ]; then \
        echo "  Branch: $(git -C {{MSI_NAV_DIR}} branch --show-current 2>/dev/null)"; \
        echo "  Commit: $(git -C {{MSI_NAV_DIR}} log -1 --format='%h %s' 2>/dev/null)"; \
        echo "  Dirty:  $(git -C {{MSI_NAV_DIR}} status --short 2>/dev/null | wc -l | tr -d ' ') file(s) changed"; \
    fi
    @echo ""
    @echo "  ── onboarded (in progress) ───────────────────────────────────────"
    @echo "  Path:   {{ONBOARDED_DIR}}"
    @if [ -d "{{ONBOARDED_DIR}}/.git" ]; then \
        echo "  Branch: $(git -C {{ONBOARDED_DIR}} branch --show-current 2>/dev/null)"; \
        echo "  Commit: $(git -C {{ONBOARDED_DIR}} log -1 --format='%h %s' 2>/dev/null)"; \
    fi
    @echo "  Tenant: {{OB_TENANT}}"
    @[ -f "{{OB_GENERATED}}/nav_maps.zsh" ] \
        && echo "  Adapters: ✔ generated" \
        || echo "  Adapters: ✗ missing — run: just generate"
    @echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STABLE STATE — snapshot + verify msi-nav has not changed
# ─────────────────────────────────────────────────────────────────────────────

snapshot:
    @echo "  Snapshotting msi-nav → {{SNAPSHOT_FILE}}"
    @find {{MSI_NAV_DIR}} -type f \( -name "*.zsh" -o -name "*.sh" -o -name "*.py" -o -name "*.json" \) \
        | sort | xargs sha256sum > {{SNAPSHOT_FILE}}
    @echo "  ✔  $(wc -l < {{SNAPSHOT_FILE}} | tr -d ' ') files recorded"
    @[ -d "{{MSI_NAV_DIR}}/.git" ] \
        && echo "  At commit: $(git -C {{MSI_NAV_DIR}} log -1 --format='%h %s')" || true

verify-stable:
    @[ -f "{{SNAPSHOT_FILE}}" ] || { echo "  No snapshot. Run: just snapshot"; exit 1; }
    @find {{MSI_NAV_DIR}} -type f \( -name "*.zsh" -o -name "*.sh" -o -name "*.py" -o -name "*.json" \) \
        | sort | xargs sha256sum > /tmp/ob_msinav_check.sha
    @diff -q {{SNAPSHOT_FILE}} /tmp/ob_msinav_check.sha > /dev/null 2>&1 \
        && echo "  ✔  msi-nav STABLE — no changes since snapshot" \
        || { echo "  ✗  msi-nav has changed:"; diff {{SNAPSHOT_FILE}} /tmp/ob_msinav_check.sha | grep '^[<>]' | head -20; exit 1; }

verify-zshrc:
    @echo "  Checking ~/.zshrc for msi-nav …"
    @grep -n "msi-nav\|msi_nav\|msi_domain" ~/.zshrc 2>/dev/null \
        && echo "  ✔  msi-nav wired into ~/.zshrc" \
        || echo "  ✗  msi-nav not found in ~/.zshrc"

check: verify-stable verify-zshrc status

which-msi:
    @echo "  In your current login shell, 'msi' resolves to:"
    @zsh -i -c 'type msi 2>/dev/null || echo "(not found)"'

# ─────────────────────────────────────────────────────────────────────────────
# GENERATION
# ─────────────────────────────────────────────────────────────────────────────

generate:
    @echo "  Validating {{OB_TENANT}} domain.json …"
    @cd {{ONBOARDED_DIR}} && python3 {{OB_VALIDATE}} --tenant {{OB_TENANT}}
    @echo "  Generating adapters …"
    @cd {{ONBOARDED_DIR}} && python3 {{OB_GENERATE}} --tenant {{OB_TENANT}}
    @echo "  ✔  {{OB_GENERATED}}/"
    @ls -1 {{OB_GENERATED}}/

generate-all:
    @cd {{ONBOARDED_DIR}} && python3 {{OB_VALIDATE}} --all
    @cd {{ONBOARDED_DIR}} && python3 {{OB_GENERATE}} --all
    @echo "  ✔  All tenants generated"

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE SHELL — onboarded active, msi-nav inactive
# ─────────────────────────────────────────────────────────────────────────────

shell:
    @just _check-generated
    @echo ""
    @echo "  ── Onboarded shell (tenant: {{OB_TENANT}}) ───────────────────────"
    @echo "  msi-nav is NOT active in this session."
    @echo "  Commands: msi where bind  /  msi status 36  /  msi explain fnol"
    @echo "  Type 'exit' to return to your normal shell."
    @echo ""
    @zsh --no-rcs -c '{{OB_SOURCE_BLOCK}}; echo "  ✔  onboarded ready"; exec zsh --no-rcs' || true

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE TESTS — four canonical commands, onboarded engine
# ─────────────────────────────────────────────────────────────────────────────

smoke:
    @just _check-generated
    @echo ""
    @echo "  ── Smoke: {{OB_TENANT}} tenant ───────────────────────────────────"
    @just _run-cmd "onboarded where bind"
    @just _run-cmd "onboarded status 36"
    @just _run-cmd "onboarded explain fnol"
    @just _run-cmd "onboarded product renters"
    @echo "  ── Smoke complete ────────────────────────────────────────────────"

# Run a single command through onboarded. Usage: just run "onboarded where bind"
# Note: use 'onboarded' not 'msi' — the msi alias only works in your login shell
run CMD:
    @just _check-generated
    @just _run-cmd "{{CMD}}"

# ─────────────────────────────────────────────────────────────────────────────
# BATS TEST SUITES
# ─────────────────────────────────────────────────────────────────────────────

# Run all three bats suites
test:
    @just _check-generated
    @echo ""
    @echo "  ── bats: test_nav_generic ────────────────────────────────────────"
    @{{BATS}} {{ONBOARDED_DIR}}/packages/cli/tests/bats/nav/test_nav_generic.bats --formatter tap
    @echo ""
    @echo "  ── bats: test_nav_msi ────────────────────────────────────────────"
    @{{BATS}} {{ONBOARDED_DIR}}/packages/cli/tests/bats/nav/test_nav_msi.bats --formatter tap
    @echo ""
    @echo "  ── bats: test_scan_msi ───────────────────────────────────────────"
    @{{BATS}} {{ONBOARDED_DIR}}/packages/cli/tests/bats/scan/test_scan_msi.bats --formatter tap

test-nav:
    @just _check-generated
    @{{BATS}} {{ONBOARDED_DIR}}/packages/cli/tests/bats/nav/test_nav_msi.bats --formatter tap

test-generic:
    @just _check-generated
    @{{BATS}} {{ONBOARDED_DIR}}/packages/cli/tests/bats/nav/test_nav_generic.bats --formatter tap

test-scan:
    @just _check-generated
    @{{BATS}} {{ONBOARDED_DIR}}/packages/cli/tests/bats/scan/test_scan_msi.bats --formatter tap

# ─────────────────────────────────────────────────────────────────────────────
# DIFF — onboarded output vs msi-nav output
# ─────────────────────────────────────────────────────────────────────────────

# Usage: just diff "msi where bind"
diff CMD:
    @just _check-generated
    @echo "  Capturing msi-nav …"
    @zsh --no-rcs -c ' \
        source "{{MSI_NAV_DIR}}/msi_domain.zsh" 2>/dev/null; \
        source "{{MSI_NAV_DIR}}/msi_nav.zsh" 2>/dev/null; \
        {{CMD}} \
    ' > /tmp/ob_diff_a.txt 2>&1 || true
    @echo "  Capturing onboarded …"
    @zsh --no-rcs -c '{{OB_SOURCE_BLOCK}}; {{CMD}}' > /tmp/ob_diff_b.txt 2>&1 || true
    @echo ""
    @echo "  ── diff msi-nav (a) vs onboarded (b): {{CMD}} ───────────────────"
    @if command -v delta > /dev/null 2>&1; then \
        diff /tmp/ob_diff_a.txt /tmp/ob_diff_b.txt | delta --no-gitconfig --side-by-side 2>/dev/null \
            || diff -u /tmp/ob_diff_a.txt /tmp/ob_diff_b.txt || true; \
    else \
        diff -u /tmp/ob_diff_a.txt /tmp/ob_diff_b.txt || true; \
    fi

diff-suite:
    @just diff "msi where bind"
    @just diff "msi status 36"
    @just diff "msi explain fnol"
    @just diff "msi product renters"
    @just diff "msi portal avalon"

# ─────────────────────────────────────────────────────────────────────────────
# PR-3 CHECKPOINT — the full gate that must pass before moving to PR-4
# ─────────────────────────────────────────────────────────────────────────────
#
# What this checks:
#   1. msi-nav is still untouched (snapshot diff)
#   2. Adapters generate cleanly from valid domain.json
#   3. Four canonical smoke commands produce output without error
#   4. All three bats suites pass
#   5. onboarded dispatcher registers msi() correctly
#   6. diff-suite shows onboarded output is a superset of msi-nav output
#
# Usage: just checkpoint-pr3

checkpoint-pr3:
    @echo ""
    @echo "══════════════════════════════════════════════════════════════════"
    @echo "  PR-3 CHECKPOINT"
    @echo "══════════════════════════════════════════════════════════════════"
    @echo ""

    @echo "  [1/6] Verifying msi-nav is stable …"
    @just verify-stable
    @echo ""

    @echo "  [2/6] Generate + validate adapters …"
    @just generate
    @echo ""

    @echo "  [3/6] Smoke test — four canonical commands …"
    @just smoke
    @echo ""

    @echo "  [4/6] bats test suites …"
    @just test
    @echo ""

    @echo "  [5/6] Dispatcher registration check …"
    @just _dispatcher-check
    @echo ""

    @echo "  [6/6] Diff suite — onboarded output vs msi-nav …"
    @just diff-suite
    @echo ""

    @echo "══════════════════════════════════════════════════════════════════"
    @echo "  PR-3 CHECKPOINT COMPLETE"
    @echo "  If all 6 steps show ✔ or clean output → merge feat/cli-engines"
    @echo "  Then: git checkout main && git merge feat/cli-engines"
    @echo "  Then: git checkout -b feat/portal"
    @echo "══════════════════════════════════════════════════════════════════"
    @echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PR GATES — one command per PR
# ─────────────────────────────────────────────────────────────────────────────

pr3: checkpoint-pr3

pr4:
    @just generate
    @just smoke
    @echo "  Running pytest …"
    @cd {{ONBOARDED_DIR}}/packages/api && pytest --tb=short -q

pr5:
    @just generate
    @echo "  TypeScript typecheck …"
    @cd {{ONBOARDED_DIR}} && npm run typecheck
    @echo "  Angular portal build …"
    @cd {{ONBOARDED_DIR}} && npm run portal:build

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL HELPERS
# ─────────────────────────────────────────────────────────────────────────────

_check-generated:
    @[ -f "{{OB_GENERATED}}/nav_maps.zsh" ] || { \
        echo "  ✗  Adapters missing for tenant '{{OB_TENANT}}'. Run: just generate"; \
        exit 1; \
    }

_run-cmd CMD:
    @echo "  \$ {{CMD}}"
    @zsh --no-rcs -c '{{OB_SOURCE_BLOCK}}; {{CMD}}' || true
    @echo ""

_dispatcher-check:
    @zsh --no-rcs -c ' \
        export OB_TENANT={{OB_TENANT}} OB_NAV_SLUG={{uppercase(OB_TENANT)}}; \
        source "{{OB_GENERATED}}/nav_maps.zsh"; \
        source "{{OB_GENERATED}}/scan_rules.zsh"; \
        source "{{OB_DISPATCHER}}" 2>/dev/null; \
        if functions onboarded | grep -q onboarded; then \
            echo "  ✔  onboarded() registered"; \
        else \
            echo "  ✗  onboarded() NOT registered"; exit 1; \
        fi; \
        if functions msi | grep -q msi; then \
            echo "  ✔  msi() alias registered"; \
        else \
            echo "  ✗  msi() NOT registered"; exit 1; \
        fi \
    '
