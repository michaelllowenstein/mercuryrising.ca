"""
tests/test_gap_detection.py — Tests for SPIKE-1.1 (operation gaps) and
SPIKE-1.2 (stale path detection).
"""
from __future__ import annotations

import os
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from onboarded_feedback.gap_detection.operation_gaps import (
    detect_missing_operations,
    OperationGapReport,
    TYPO_SIMILARITY_THRESHOLD,
    MIN_MISS_COUNT,
    _similarity,
    _best_match,
)
from onboarded_feedback.gap_detection.stale_paths import (
    detect_stale_paths,
    _diagnose_single_path,
    PathDiagnosis,
)
from onboarded_feedback.domain_loader import TenantDomainView


class TestSimilarityHelpers:
    def test_identical_strings(self) -> None:
        assert _similarity("bind", "bind") == 1.0

    def test_completely_different(self) -> None:
        assert _similarity("bind", "xyzw") < 0.3

    def test_one_char_typo(self) -> None:
        ratio = _similarity("bnd", "bind")
        assert ratio > 0.7   # Should be classified as a typo

    def test_best_match_finds_closest(self) -> None:
        existing = ["bind", "quote", "payment", "reinstate"]
        key, ratio = _best_match("bnd", existing)
        assert key == "bind"
        assert ratio > TYPO_SIMILARITY_THRESHOLD

    def test_best_match_empty_existing(self) -> None:
        key, ratio = _best_match("anything", [])
        assert key is None
        assert ratio == 0.0


class TestOperationGapDetection:
    def test_genuine_missing_ops_are_surfaced(self, seeded_misses) -> None:
        report = detect_missing_operations(seeded_misses, since_days=90, min_count=2)
        candidate_keys = [c.key for c in report.candidates]
        assert "transfer"  in candidate_keys
        assert "resubmit"  in candidate_keys

    def test_typos_are_filtered(self, seeded_misses) -> None:
        report = detect_missing_operations(seeded_misses, since_days=90, min_count=2)
        candidate_keys = [c.key for c in report.candidates]
        typo_keys      = [c.key for c in report.typos_filtered]
        # 'bnd' is close to 'bind' — should be filtered as typo
        assert "bnd" not in candidate_keys
        assert "bnd" in typo_keys

    def test_below_min_count_excluded(self, seeded_misses) -> None:
        report = detect_missing_operations(seeded_misses, since_days=90, min_count=2)
        all_keys = [c.key for c in report.candidates + report.typos_filtered]
        # 'paymet' had only 1 miss — below default MIN_MISS_COUNT of 2
        assert "paymet" not in all_keys

    def test_candidates_ranked_by_miss_count(self, seeded_misses) -> None:
        report = detect_missing_operations(seeded_misses, since_days=90, min_count=2)
        assert len(report.candidates) >= 2
        # First candidate should have highest miss count
        assert report.candidates[0].miss_count >= report.candidates[1].miss_count

    def test_no_misses_produces_empty_report(self, sample_domain) -> None:
        # No telemetry seeded — should return empty candidates
        report = detect_missing_operations(sample_domain, since_days=90, min_count=1)
        assert report.candidates == []

    def test_existing_operations_not_reported_as_missing(self, seeded_misses) -> None:
        """Hit events for 'bind' should never appear as missing operation."""
        report = detect_missing_operations(seeded_misses, since_days=90, min_count=1)
        candidate_keys = [c.key for c in report.candidates]
        assert "bind"  not in candidate_keys
        assert "quote" not in candidate_keys

    def test_custom_typo_threshold(self, seeded_misses) -> None:
        """A very HIGH threshold means even close matches (bnd ~ bind) pass as candidates."""
        # threshold=0.99 means only 99%+ similarity counts as a typo.
        # 'bnd' vs 'bind' is ~0.85 similar — below 0.99 → NOT classified as typo.
        report = detect_missing_operations(
            seeded_misses, since_days=90, min_count=1, typo_threshold=0.99
        )
        candidate_keys = [c.key for c in report.candidates]
        assert "bnd" in candidate_keys


class TestStalePathDetection:
    def test_present_paths_counted(self, sample_domain: TenantDomainView, tmp_path: Path) -> None:
        """Create actual files at the expected paths and verify 'present' count."""
        # Set up mock repo directories
        api_dir = tmp_path / "tco-api"
        (api_dir / "Controllers").mkdir(parents=True)
        (api_dir / "Controllers" / "PolicyBindController.cs").touch()
        (api_dir / "Controllers" / "QuoteController.cs").touch()
        (api_dir / "Controllers" / "PaymentController.cs").touch()
        (api_dir / "Controllers" / "ReinstateController.cs").touch()
        (api_dir / "Services").mkdir(parents=True)
        (api_dir / "Services" / "PolicyBindService.cs").touch()
        (api_dir / "Services" / "QuoteService.cs").touch()
        (api_dir / "Services" / "PaymentService.cs").touch()
        (api_dir / "Queues").mkdir(parents=True)
        (api_dir / "Queues" / "PaymentQueue.cs").touch()

        os.environ["TCO_API_DIR"] = str(api_dir)
        try:
            report = detect_stale_paths(sample_domain)
            assert report.present_count == 8   # 4 controllers + 3 services + 1 queue
            assert report.stale_count == 0
        finally:
            del os.environ["TCO_API_DIR"]

    def test_missing_file_classified_as_stale(self, sample_domain, tmp_path: Path) -> None:
        """Files that don't exist on disk and can't be found in git → stale/deleted."""
        api_dir = tmp_path / "tco-api"
        api_dir.mkdir(parents=True)
        # Do NOT create the files

        os.environ["TCO_API_DIR"] = str(api_dir)
        try:
            with patch(
                "onboarded_feedback.gap_detection.stale_paths._find_rename",
                return_value=(None, None, None),
            ), patch(
                "onboarded_feedback.gap_detection.stale_paths._find_deletion",
                return_value=("2026-01-15", "abc1234"),
            ):
                report = detect_stale_paths(sample_domain)
                assert report.stale_count > 0
                deleted = [d for d in report.stale if d.status == "deleted"]
                assert len(deleted) > 0
                assert deleted[0].git_commit_date == "2026-01-15"
        finally:
            del os.environ["TCO_API_DIR"]

    def test_renamed_file_produces_replacement_suggestion(
        self, sample_domain, tmp_path: Path
    ) -> None:
        api_dir = tmp_path / "tco-api"
        api_dir.mkdir(parents=True)

        os.environ["TCO_API_DIR"] = str(api_dir)
        try:
            with patch(
                "onboarded_feedback.gap_detection.stale_paths._find_rename",
                return_value=(
                    "Controllers/PolicyBindControllerV2.cs",
                    "2026-03-01",
                    "deadbeef",
                ),
            ):
                report = detect_stale_paths(sample_domain)
                renamed = [d for d in report.stale if d.status == "renamed"]
                assert len(renamed) > 0
                assert renamed[0].suggested_replacement == "TCO-API:Controllers/PolicyBindControllerV2.cs"
        finally:
            del os.environ["TCO_API_DIR"]

    def test_unresolvable_when_env_var_not_set(self, sample_domain) -> None:
        """Paths whose repo has no env var AND no default_dir are unresolvable."""
        from unittest.mock import patch
        from onboarded_feedback.domain_loader import RepoConfig

        # Override repos to have no default_dir and ensure env vars are absent
        empty_repos = {
            "TCO-API": RepoConfig(alias="TCO-API", env_var="TCO_API_DIR_MISSING_XYZ", default_dir=""),
            "TCO-WEB": RepoConfig(alias="TCO-WEB", env_var="TCO_WEB_DIR_MISSING_XYZ", default_dir=""),
        }
        os.environ.pop("TCO_API_DIR_MISSING_XYZ", None)
        os.environ.pop("TCO_WEB_DIR_MISSING_XYZ", None)

        with patch.object(sample_domain, "repos", empty_repos):
            report = detect_stale_paths(sample_domain)

        assert report.unresolvable_count > 0
        assert report.stale_count == 0