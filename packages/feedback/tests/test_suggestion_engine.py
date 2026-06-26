"""
tests/test_suggestion_engine.py — Tests for Phase 2: the suggestion store,
git scanner, and rule effectiveness analyser.
"""
from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from onboarded_feedback.suggestion_engine.suggestions import (
    SuggestionStore,
    OperationPathSuggestion,
    StalePathSuggestion,
)
from onboarded_feedback.suggestion_engine.git_scanner import (
    scan_git_new_files,
    _classify_file,
    _tokenize,
)
from onboarded_feedback.suggestion_engine.rule_effectiveness import (
    analyze_rule_effectiveness,
    RuleEffectivenessReport,
)
from onboarded_feedback.telemetry.store import record_scan_event


# ── SuggestionStore ───────────────────────────────────────────────────────────

class TestSuggestionStore:
    def test_empty_store_on_first_load(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        assert store.total_count == 0
        assert store.tenant == "test"

    def test_add_and_save_operation_path(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        store.add_operation_path(
            operation_key="bind",
            path_role="controllers",
            encoded_path="TCO-API:Controllers/NewBindController.cs",
            source="ob_learn",
            confidence="high",
        )
        store.save()

        reloaded = SuggestionStore.load("test")
        assert reloaded.total_count == 1
        assert reloaded.operation_paths[0].operation_key == "bind"
        assert reloaded.operation_paths[0].encoded_path == "TCO-API:Controllers/NewBindController.cs"

    def test_add_operation_path_deduplicates(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        store.add_operation_path("bind", "controllers", "TCO:Foo.cs", confidence="medium")
        store.add_operation_path("bind", "controllers", "TCO:Foo.cs", confidence="high")
        # Should still only have 1 entry, with updated confidence
        assert len(store.operation_paths) == 1
        assert store.operation_paths[0].confidence == "high"

    def test_add_stale_path(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        store.add_stale_path(
            operation_key="bind",
            path_role="controllers",
            old_path="TCO-API:Controllers/OldController.cs",
            status="renamed",
            suggested_replacement="TCO-API:Controllers/NewController.cs",
            git_commit_date="2026-03-01",
        )
        store.save()

        reloaded = SuggestionStore.load("test")
        assert len(reloaded.stale_paths) == 1
        sp = reloaded.stale_paths[0]
        assert sp.status == "renamed"
        assert sp.suggested_replacement == "TCO-API:Controllers/NewController.cs"

    def test_add_missing_operation(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        store.add_missing_operation(key="transfer", miss_count=12,
                                    closest_existing="reinstate", closest_similarity=0.45)
        store.save()

        reloaded = SuggestionStore.load("test")
        assert len(reloaded.missing_operations) == 1
        assert reloaded.missing_operations[0].key == "transfer"
        assert reloaded.missing_operations[0].miss_count == 12

    def test_scan_rule_suggestion(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        store.add_scan_rule_suggestion(
            rule_id="no_hardcoded_secrets",
            suggestion_type="pattern_review",
            rationale="Never fired in 90 days.",
            current_severity="critical",
        )
        store.save()

        reloaded = SuggestionStore.load("test")
        assert len(reloaded.scan_rule_tuning) == 1
        assert reloaded.scan_rule_tuning[0].rule_id == "no_hardcoded_secrets"

    def test_multiple_suggestion_types(self, isolated_home: Path) -> None:
        store = SuggestionStore.load("test")
        store.add_operation_path("bind", "controllers", "TCO:A.cs")
        store.add_stale_path("quote", "services", "TCO:B.cs", "deleted")
        store.add_missing_operation("transfer", 5, None, 0.0)
        assert store.total_count == 3

    def test_render_apply_patch_contains_suggested_markers(
        self, isolated_home: Path, domain_path: Path
    ) -> None:
        store = SuggestionStore.load("test")
        store.add_operation_path(
            operation_key="bind",
            path_role="controllers",
            encoded_path="TCO-API:Controllers/PolicyBindControllerV2.cs",
            source="ob_learn",
            confidence="high",
        )
        patch_str = store.render_apply_patch(domain_path)

        assert "// SUGGESTED" in patch_str
        assert "PolicyBindControllerV2.cs" in patch_str
        assert "high confidence" in patch_str

    def test_render_apply_patch_contains_stale_markers(
        self, isolated_home: Path, domain_path: Path
    ) -> None:
        store = SuggestionStore.load("test")
        store.add_stale_path(
            operation_key="bind",
            path_role="controllers",
            old_path="TCO-API:Controllers/PolicyBindController.cs",
            status="renamed",
            suggested_replacement="TCO-API:Controllers/PolicyBindControllerV2.cs",
        )
        patch_str = store.render_apply_patch(domain_path)

        assert "// STALE" in patch_str

    def test_render_apply_patch_has_header(
        self, isolated_home: Path, domain_path: Path
    ) -> None:
        store = SuggestionStore.load("test")
        store.add_operation_path("bind", "controllers", "TCO:X.cs")
        patch_str = store.render_apply_patch(domain_path)

        assert "validate_domain.py" in patch_str
        assert "generate_adapters.py" in patch_str


# ── Git scanner ───────────────────────────────────────────────────────────────

class TestGitScanner:
    def test_tokenize_camel_case(self) -> None:
        tokens = _tokenize("PolicyBindController")
        assert "policy" in tokens
        assert "bind" in tokens
        assert "controller" in tokens

    def test_tokenize_operation_key(self) -> None:
        tokens = _tokenize("bind")
        assert "bind" in tokens

    def test_classify_high_confidence(self, sample_domain) -> None:
        # A file named 'PolicyBindController.cs' in the Controllers dir
        # should classify as HIGH for operation 'bind'
        match = _classify_file(
            "Controllers/PolicyBindController.cs",
            "TCO-API",
            sample_domain,
        )
        assert match is not None
        assert match.confidence == "high"
        assert "bind" in match.matched_operations

    def test_classify_no_match_returns_none(self, sample_domain) -> None:
        # A completely unrelated file should not match
        match = _classify_file("XyzUnrelatedHelper.cs", "TCO-API", sample_domain)
        assert match is None

    def test_scan_git_returns_reports(self, sample_domain, tmp_path: Path) -> None:
        """Mock git to return new files; verify classification runs."""
        api_dir = tmp_path / "tco-api"
        api_dir.mkdir()

        import os
        os.environ["TCO_API_DIR"] = str(api_dir)

        try:
            with patch(
                "onboarded_feedback.suggestion_engine.git_scanner._git_new_files",
                return_value=["Controllers/PolicyBindControllerV2.cs"],
            ):
                reports = scan_git_new_files(sample_domain, since_ref="30 days ago")

            assert len(reports) >= 1
            tco_report = next((r for r in reports if r.repo_alias == "TCO-API"), None)
            assert tco_report is not None
            assert tco_report.new_files_examined == 1
            assert len(tco_report.high_confidence) == 1
            assert "bind" in tco_report.high_confidence[0].matched_operations
        finally:
            del os.environ["TCO_API_DIR"]

    def test_non_relevant_extension_skipped(self, sample_domain, tmp_path: Path) -> None:
        api_dir = tmp_path / "tco-api"
        api_dir.mkdir()

        import os
        os.environ["TCO_API_DIR"] = str(api_dir)

        try:
            with patch(
                "onboarded_feedback.suggestion_engine.git_scanner._git_new_files",
                return_value=["README.md", "config.yml", "image.png"],
            ):
                reports = scan_git_new_files(sample_domain, since_ref="30 days ago")

            tco_report = next((r for r in reports if r.repo_alias == "TCO-API"), None)
            assert tco_report is not None
            assert tco_report.new_files_examined == 0
        finally:
            del os.environ["TCO_API_DIR"]


# ── Rule effectiveness ────────────────────────────────────────────────────────

class TestRuleEffectiveness:
    def test_never_firing_rule_detected(
        self, isolated_home: Path, sample_domain
    ) -> None:
        # Seed scan events for some rules but not 'no_hardcoded_secrets'
        for _ in range(10):
            record_scan_event("test", "no_empty_catch", finding_count=1)
        # no_hardcoded_secrets has no events → never_firing

        report = analyze_rule_effectiveness(sample_domain, since_days=90)
        never_ids = [r.rule_id for r in report.never_firing]
        assert "no_hardcoded_secrets" in never_ids

    def test_always_firing_rule_detected(
        self, isolated_home: Path, sample_domain
    ) -> None:
        # Seed a rule that fires a lot and is never resolved
        for _ in range(20):
            record_scan_event("test", "no_todo_without_ticket",
                              finding_count=25, acted_on=False)

        report = analyze_rule_effectiveness(sample_domain, since_days=90)
        always_ids = [r.rule_id for r in report.always_firing]
        assert "no_todo_without_ticket" in always_ids

    def test_healthy_rule_detected(
        self, isolated_home: Path, sample_domain
    ) -> None:
        # A rule that fires occasionally and is resolved
        for i in range(10):
            record_scan_event("test", "no_empty_catch",
                              finding_count=1, acted_on=(i % 2 == 0))

        report = analyze_rule_effectiveness(sample_domain, since_days=90)
        healthy_ids = [r.rule_id for r in report.healthy]
        assert "no_empty_catch" in healthy_ids

    def test_rules_with_no_telemetry_appear_in_never_firing(
        self, isolated_home: Path, sample_domain
    ) -> None:
        """Rules in domain.json with zero telemetry should be flagged."""
        report = analyze_rule_effectiveness(sample_domain, since_days=90)
        never_ids = [r.rule_id for r in report.never_firing]
        # All three rules have no telemetry — all should be in never_firing
        assert "no_hardcoded_secrets" in never_ids
        assert "no_empty_catch" in never_ids
        assert "no_todo_without_ticket" in never_ids

    def test_insufficient_data_classification(
        self, isolated_home: Path, sample_domain
    ) -> None:
        """Rules with fewer than NEVER_FIRING_MIN_RUNS should be 'insufficient_data'."""
        # Seed only 2 runs (below default threshold of 5)
        for _ in range(2):
            record_scan_event("test", "no_hardcoded_secrets", finding_count=0)

        report = analyze_rule_effectiveness(sample_domain, since_days=90)
        insufficient_ids = [r.rule_id for r in report.insufficient_data]
        assert "no_hardcoded_secrets" in insufficient_ids