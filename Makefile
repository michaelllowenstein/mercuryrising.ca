# ─────────────────────────────────────────────────────────────────────────────
# Makefile — msi-nav ↔ onboarded swap harness + PR gate runner
#
# WHAT IS .bats?
# ──────────────
# .bats files are test scripts for bats-core (Bash Automated Testing System).
# Each @test block is an independent test case run in a clean subshell.
# Output is TAP (Test Anything Protocol): "ok N description" or "not ok N ...".
#
# The anatomy of a bats test:
#
#   @test "msi where bind: exits 0" {
#       run ob_where bind          # captures stdout, stderr, exit code
#       [ "$status" -eq 0 ]        # assert exit code
#       [[ "$output" == *"BasePolicyController"* ]]
#   }
#
# Key bats variables set by `run`:
#   $$status — exit code    $$output — combined stdout+stderr
#
# Our three suites:
#   test_nav_generic.bats  — generic tenant, 14 tests
#   test_nav_msi.bats      — MSI tenant, 34 tests
#   test_scan_msi.bats     — scan engine, 12 tests
#
# ─────────────────────────────────────────────────────────────────────────────

# ── Configurable ──────────────────────────────────────────────────────────────
MSI_NAV_DIR    ?= $(HOME)/msi-nav
ONBOARDED_DIR  ?= $(HOME)/workspaces/miloseng/onboarded
OB_TENANT      ?= msi
BATS           ?= $(shell which bats 2>/dev/null || echo bats)

# ── Derived ───────────────────────────────────────────────────────────────────
OB_TENANT_UPPER := $(shell echo $(OB_TENANT) | tr '[:lower:]' '[:upper:]')
OB_GENERATED    := $(ONBOARDED_DIR)/packages/core/generated/$(OB_TENANT)
OB_DISPATCHER   := $(ONBOARDED_DIR)/packages/cli/src/ob_dispatcher.zsh
OB_VALIDATE     := $(ONBOARDED_DIR)/packages/core/scripts/validate_domain.py
OB_GENERATE     := $(ONBOARDED_DIR)/packages/core/scripts/generate_adapters.py
SNAPSHOT_FILE   := $(ONBOARDED_DIR)/.msi-nav-snapshot.sha
ZSH             := $(shell which zsh)
BATS_NAV_MSI    := $(ONBOARDED_DIR)/packages/cli/tests/bats/nav/test_nav_msi.bats
BATS_NAV_GEN    := $(ONBOARDED_DIR)/packages/cli/tests/bats/nav/test_nav_generic.bats
BATS_SCAN_MSI   := $(ONBOARDED_DIR)/packages/cli/tests/bats/scan/test_scan_msi.bats

# ── Source block — load onboarded engine in a clean Zsh subshell ─────────────
# No ~/.zshrc, no msi-nav. Used by every CLI invocation target.
define OB_SOURCE
export OB_TENANT=$(OB_TENANT) OB_NAV_SLUG=$(OB_TENANT_UPPER); \
source "$(OB_GENERATED)/nav_maps.zsh"; \
source "$(OB_GENERATED)/scan_rules.zsh"; \
source "$(ONBOARDED_DIR)/packages/cli/src/core/ob_core_display.zsh"; \
source "$(ONBOARDED_DIR)/packages/cli/src/core/ob_core_loader.zsh"; \
source "$(ONBOARDED_DIR)/packages/cli/src/nav/ob_nav_engine.zsh"; \
source "$(ONBOARDED_DIR)/packages/cli/src/scan/ob_scan_engine.zsh"; \
source "$(OB_DISPATCHER)" 2>/dev/null
endef

.PHONY: default help status snapshot verify-stable verify-zshrc check which-msi \
        generate generate-all shell smoke run test test-nav test-generic test-scan \
        diff diff-suite checkpoint-pr3 pr3 pr4 pr5 \
        _check-generated _dispatcher-check

# ─────────────────────────────────────────────────────────────────────────────
default: help

help:
	@echo ""
	@echo "  msi-nav ↔ onboarded harness"
	@echo "  MSI_NAV_DIR=$(MSI_NAV_DIR)  ONBOARDED_DIR=$(ONBOARDED_DIR)  OB_TENANT=$(OB_TENANT)"
	@echo ""
	@echo "  STABLE STATE"
	@echo "    make snapshot          record SHA manifest of msi-nav"
	@echo "    make verify-stable     confirm msi-nav unchanged"
	@echo "    make verify-zshrc      confirm msi-nav wired in .zshrc"
	@echo "    make check             all stability checks + status"
	@echo "    make which-msi         show what 'msi' is in current shell"
	@echo ""
	@echo "  GENERATION"
	@echo "    make generate          validate + generate for OB_TENANT"
	@echo "    make generate-all      validate + generate all tenants"
	@echo ""
	@echo "  INTERACTIVE"
	@echo "    make shell             onboarded Zsh session (msi-nav inactive)"
	@echo "    make smoke             4 canonical commands via onboarded"
	@echo "    CMD='msi where bind' make run"
	@echo ""
	@echo "  TESTING (bats)"
	@echo "    make test              all 3 bats suites"
	@echo "    make test-nav          MSI nav bats only"
	@echo "    make test-generic      generic nav bats only"
	@echo "    make test-scan         scan bats only"
	@echo ""
	@echo "  DIFF"
	@echo "    CMD='msi where bind' make diff"
	@echo "    make diff-suite        diff all canonical commands"
	@echo ""
	@echo "  PR GATES"
	@echo "    make checkpoint-pr3    full 6-step PR-3 gate (run before merging)"
	@echo "    make pr4               generate + smoke + pytest"
	@echo "    make pr5               generate + typecheck + portal build"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STATUS
# ─────────────────────────────────────────────────────────────────────────────
status:
	@echo ""
	@echo "  ── msi-nav (stable) ──────────────────────────────────────────────"
	@echo "  Path:   $(MSI_NAV_DIR)"
	@[ -d "$(MSI_NAV_DIR)/.git" ] && \
		echo "  Branch: $$(git -C $(MSI_NAV_DIR) branch --show-current 2>/dev/null)" && \
		echo "  Commit: $$(git -C $(MSI_NAV_DIR) log -1 --format='%h %s' 2>/dev/null)" || true
	@echo ""
	@echo "  ── onboarded (in progress) ───────────────────────────────────────"
	@echo "  Path:   $(ONBOARDED_DIR)"
	@[ -d "$(ONBOARDED_DIR)/.git" ] && \
		echo "  Branch: $$(git -C $(ONBOARDED_DIR) branch --show-current 2>/dev/null)" && \
		echo "  Commit: $$(git -C $(ONBOARDED_DIR) log -1 --format='%h %s' 2>/dev/null)" || true
	@echo "  Tenant: $(OB_TENANT)"
	@[ -f "$(OB_GENERATED)/nav_maps.zsh" ] \
		&& echo "  Adapters: ✔ generated" \
		|| echo "  Adapters: ✗ missing — run: make generate"
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# STABLE STATE
# ─────────────────────────────────────────────────────────────────────────────
snapshot:
	@echo "  Snapshotting msi-nav → $(SNAPSHOT_FILE)"
	@find $(MSI_NAV_DIR) -type f \( -name "*.zsh" -o -name "*.sh" -o -name "*.py" -o -name "*.json" \) \
		| sort | xargs sha256sum > $(SNAPSHOT_FILE)
	@printf "  ✔  %s files recorded\n" "$$(wc -l < $(SNAPSHOT_FILE) | tr -d ' ')"

verify-stable:
	@[ -f "$(SNAPSHOT_FILE)" ] || { echo "  No snapshot. Run: make snapshot"; exit 1; }
	@find $(MSI_NAV_DIR) -type f \( -name "*.zsh" -o -name "*.sh" -o -name "*.py" -o -name "*.json" \) \
		| sort | xargs sha256sum > /tmp/ob_msinav_check.sha
	@diff -q $(SNAPSHOT_FILE) /tmp/ob_msinav_check.sha > /dev/null 2>&1 \
		&& echo "  ✔  msi-nav STABLE — no changes since snapshot" \
		|| { echo "  ✗  msi-nav has changed:"; diff $(SNAPSHOT_FILE) /tmp/ob_msinav_check.sha | grep '^[<>]' | head -20; exit 1; }

verify-zshrc:
	@grep -n "msi-nav\|msi_nav\|msi_domain" ~/.zshrc 2>/dev/null \
		&& echo "  ✔  msi-nav wired into ~/.zshrc" \
		|| echo "  ✗  msi-nav not found in ~/.zshrc"

which-msi:
	@$(ZSH) -i -c 'type msi 2>/dev/null || echo "(not found)"'

check: verify-stable verify-zshrc status

# ─────────────────────────────────────────────────────────────────────────────
# GENERATION
# ─────────────────────────────────────────────────────────────────────────────
generate: _check-onboarded
	@echo "  Validating $(OB_TENANT) domain.json …"
	@cd $(ONBOARDED_DIR) && python3 $(OB_VALIDATE) --tenant $(OB_TENANT)
	@echo "  Generating adapters …"
	@cd $(ONBOARDED_DIR) && python3 $(OB_GENERATE) --tenant $(OB_TENANT)
	@echo "  ✔  $(OB_GENERATED)/"; ls -1 $(OB_GENERATED)/

generate-all: _check-onboarded
	@cd $(ONBOARDED_DIR) && python3 $(OB_VALIDATE) --all
	@cd $(ONBOARDED_DIR) && python3 $(OB_GENERATE) --all
	@echo "  ✔  All tenants generated"

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE SHELL
# ─────────────────────────────────────────────────────────────────────────────
shell: _check-generated
	@echo "  ── Onboarded shell (tenant: $(OB_TENANT)) ─────────────────────────"
	@echo "  msi-nav inactive. Commands: msi where bind / msi status 36 / exit"
	@$(ZSH) --no-rcs -c '$(call OB_SOURCE); echo "  ✔  onboarded ready"; exec $(ZSH) --no-rcs' || true

# ─────────────────────────────────────────────────────────────────────────────
# SMOKE TESTS
# ─────────────────────────────────────────────────────────────────────────────
smoke: _check-generated
	@echo ""; echo "  ── Smoke: $(OB_TENANT) ─────────────────────────────────────────"
	@$(MAKE) --no-print-directory CMD='onboarded where bind'     run
	@$(MAKE) --no-print-directory CMD='onboarded status 36'      run
	@$(MAKE) --no-print-directory CMD='onboarded explain fnol'   run
	@$(MAKE) --no-print-directory CMD='onboarded product renters' run
	@echo "  ── Smoke complete ───────────────────────────────────────────────"

run: _check-generated
ifndef CMD
	$(error CMD is not set. Usage: CMD='msi where bind' make run)
endif
	@echo "  $$ $(CMD)"
	@$(ZSH) --no-rcs -c '$(call OB_SOURCE); $(CMD)' || true
	@echo ""

# ─────────────────────────────────────────────────────────────────────────────
# BATS TEST SUITES
# ─────────────────────────────────────────────────────────────────────────────
test: _check-generated test-generic test-nav test-scan

test-nav: _check-generated
	@echo "  ── bats: test_nav_msi ───────────────────────────────────────────"
	@$(BATS) $(BATS_NAV_MSI) --formatter tap

test-generic: _check-generated
	@echo "  ── bats: test_nav_generic ───────────────────────────────────────"
	@$(BATS) $(BATS_NAV_GEN) --formatter tap

test-scan: _check-generated
	@echo "  ── bats: test_scan_msi ──────────────────────────────────────────"
	@$(BATS) $(BATS_SCAN_MSI) --formatter tap

# ─────────────────────────────────────────────────────────────────────────────
# DIFF
# ─────────────────────────────────────────────────────────────────────────────
diff: _check-generated
ifndef CMD
	$(error CMD is not set. Usage: CMD='msi where bind' make diff)
endif
	@$(ZSH) --no-rcs -c ' \
		source "$(MSI_NAV_DIR)/msi_domain.zsh" 2>/dev/null; \
		source "$(MSI_NAV_DIR)/msi_nav.zsh" 2>/dev/null; \
		$(CMD)' > /tmp/ob_diff_a.txt 2>&1 || true
	@$(ZSH) --no-rcs -c '$(call OB_SOURCE); $(CMD)' > /tmp/ob_diff_b.txt 2>&1 || true
	@echo "  ── diff msi-nav (a) vs onboarded (b): $(CMD) ───────────────────"
	@if command -v delta > /dev/null 2>&1; then \
		diff /tmp/ob_diff_a.txt /tmp/ob_diff_b.txt \
			| delta --no-gitconfig --side-by-side 2>/dev/null \
			|| diff -u /tmp/ob_diff_a.txt /tmp/ob_diff_b.txt || true; \
	else \
		diff -u /tmp/ob_diff_a.txt /tmp/ob_diff_b.txt || true; \
	fi

diff-suite: _check-generated
	@$(MAKE) --no-print-directory CMD='msi where bind'      diff
	@$(MAKE) --no-print-directory CMD='msi status 36'       diff
	@$(MAKE) --no-print-directory CMD='msi explain fnol'    diff
	@$(MAKE) --no-print-directory CMD='msi product renters' diff
	@$(MAKE) --no-print-directory CMD='msi portal avalon'   diff

# ─────────────────────────────────────────────────────────────────────────────
# PR-3 CHECKPOINT
# ─────────────────────────────────────────────────────────────────────────────
checkpoint-pr3:
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo "  PR-3 CHECKPOINT"
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  [1/6] Verifying msi-nav is stable …"
	@$(MAKE) --no-print-directory verify-stable
	@echo ""
	@echo "  [2/6] Generate + validate adapters …"
	@$(MAKE) --no-print-directory generate
	@echo ""
	@echo "  [3/6] Smoke test …"
	@$(MAKE) --no-print-directory smoke
	@echo ""
	@echo "  [4/6] bats suites …"
	@$(MAKE) --no-print-directory test
	@echo ""
	@echo "  [5/6] Dispatcher registration …"
	@$(MAKE) --no-print-directory _dispatcher-check
	@echo ""
	@echo "  [6/6] Diff suite …"
	@$(MAKE) --no-print-directory diff-suite
	@echo ""
	@echo "══════════════════════════════════════════════════════════════════"
	@echo "  PR-3 CHECKPOINT COMPLETE"
	@echo "  All 6 steps clean → merge feat/cli-engines, open feat/portal"
	@echo "══════════════════════════════════════════════════════════════════"
	@echo ""

pr3: checkpoint-pr3

pr4: generate smoke
	@echo "  Running pytest …"
	@cd $(ONBOARDED_DIR)/packages/api && pytest --tb=short -q

pr5: generate
	@echo "  TypeScript typecheck …"
	@cd $(ONBOARDED_DIR) && npm run typecheck
	@echo "  Angular portal build …"
	@cd $(ONBOARDED_DIR) && npm run portal:build

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL GUARDS
# ─────────────────────────────────────────────────────────────────────────────
_check-generated:
	@[ -f "$(OB_GENERATED)/nav_maps.zsh" ] || \
		{ echo "  ✗  Adapters missing. Run: make generate"; exit 1; }

_check-onboarded:
	@[ -f "$(OB_VALIDATE)" ] || \
		{ echo "  ✗  validate_domain.py not found. Check ONBOARDED_DIR=$(ONBOARDED_DIR)"; exit 1; }

_dispatcher-check:
	@$(ZSH) --no-rcs -c ' \
		export OB_TENANT=$(OB_TENANT) OB_NAV_SLUG=$(OB_TENANT_UPPER); \
		source "$(OB_GENERATED)/nav_maps.zsh"; \
		source "$(OB_GENERATED)/scan_rules.zsh"; \
		source "$(OB_DISPATCHER)" 2>/dev/null; \
		if functions onboarded | grep -q onboarded; then \
			echo "  ✔  onboarded() registered"; \
		else \
			echo "  ✗  onboarded() NOT registered"; exit 1; \
		fi; \
		if functions msi | grep -q msi; then \
			echo "  ✔  msi() alias registered"; \
		else \
			echo "  ✗  msi() NOT registered"; exit 1; \
		fi'