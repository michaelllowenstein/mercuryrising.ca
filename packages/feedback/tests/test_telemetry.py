"""
tests/test_telemetry.py — Unit tests for the telemetry store module.

Covers: write, read, summary, scan events, purge.
All writes go to isolated_home (tmp_path), never to the real ~/.onboarded.
"""
from __future__ import annotations

import time
from pathlib import Path

import pytest

from onboarded_feedback.telemetry.store import (
    TelemetryEvent,
    record_event,
    record_scan_event,
    query_summary,
    query_misses,
    query_scan_effectiveness,
    purge_old_events,
    MissRecord,
)


TENANT = "test"


class TestRecordEvent:
    def test_hit_is_written(self, isolated_home: Path) -> None:
        record_event(TelemetryEvent("command", TENANT, "where", key="bind", result="hit"))
        summary = query_summary(TENANT, since_days=1)
        assert summary.hit_count == 1
        assert summary.total_events == 1

    def test_miss_is_written(self, isolated_home: Path) -> None:
        record_event(TelemetryEvent("miss", TENANT, "where", key="unknown_op", result="miss"))
        summary = query_summary(TENANT, since_days=1)
        assert summary.miss_count == 1

    def test_partial_is_written(self, isolated_home: Path) -> None:
        record_event(TelemetryEvent("command", TENANT, "where", key="bind", result="partial"))
        summary = query_summary(TENANT, since_days=1)
        assert summary.partial_count == 1

    def test_event_without_key_is_written(self, isolated_home: Path) -> None:
        """Events like 'list' may have no key — must not raise."""
        record_event(TelemetryEvent("command", TENANT, "list", key=None, result="hit"))
        summary = query_summary(TENANT, since_days=1)
        assert summary.total_events == 1

    def test_multiple_events_accumulate(self, isolated_home: Path) -> None:
        for _ in range(5):
            record_event(TelemetryEvent("command", TENANT, "where", key="bind", result="hit"))
        for _ in range(3):
            record_event(TelemetryEvent("miss", TENANT, "where", key="ghost", result="miss"))
        summary = query_summary(TENANT, since_days=1)
        assert summary.hit_count == 5
        assert summary.miss_count == 3

    def test_tenant_isolation(self, isolated_home: Path) -> None:
        """Events for tenant A must not appear in tenant B's summary."""
        record_event(TelemetryEvent("command", "tenant_a", "where", key="op1", result="hit"))
        record_event(TelemetryEvent("miss",    "tenant_b", "where", key="op2", result="miss"))

        summary_a = query_summary("tenant_a", since_days=1)
        summary_b = query_summary("tenant_b", since_days=1)

        assert summary_a.hit_count == 1
        assert summary_a.miss_count == 0
        assert summary_b.hit_count == 0
        assert summary_b.miss_count == 1

    def test_record_is_silent_on_corrupt_path(self, tmp_path: Path, monkeypatch) -> None:
        """record_event must never raise even with an inaccessible DB path."""
        monkeypatch.setenv("HOME", "/nonexistent/totally/fake/path")
        # Should not raise:
        record_event(TelemetryEvent("command", TENANT, "where", key="x", result="hit"))


class TestQueryMisses:
    def test_miss_keys_ranked_by_frequency(self, seeded_misses) -> None:
        misses = query_misses("test", command="where", since_days=90)
        keys = [m.key for m in misses]
        # 'transfer' (×12) should rank above 'resubmit' (×7)
        assert keys.index("transfer") < keys.index("resubmit")

    def test_min_count_filter(self, seeded_misses) -> None:
        misses = query_misses("test", command="where", since_days=90, min_count=3)
        keys = [m.key for m in misses]
        # 'bnd' ×2 should be filtered out; 'paymet' ×1 definitely filtered
        assert "bnd" not in keys
        assert "paymet" not in keys

    def test_command_filter(self, isolated_home: Path) -> None:
        record_event(TelemetryEvent("miss", TENANT, "where",  key="x", result="miss"))
        record_event(TelemetryEvent("miss", TENANT, "status", key="y", result="miss"))
        where_misses = query_misses(TENANT, command="where", since_days=1)
        status_misses = query_misses(TENANT, command="status", since_days=1)
        assert all(m.command == "where" for m in where_misses)
        assert all(m.command == "status" for m in status_misses)

    def test_since_days_window(self, isolated_home: Path) -> None:
        """Events outside the lookback window must not appear."""
        import time
        from unittest.mock import patch

        # Write an event with a timestamp 200 days in the past
        old_ts = int(time.time()) - 200 * 86_400
        with patch("onboarded_feedback.telemetry.store.time") as mock_time:
            mock_time.time.return_value = float(old_ts)
            record_event(TelemetryEvent("miss", TENANT, "where", key="old_op", result="miss"))

        # Querying a 90-day window should NOT include the 200-day-old event
        misses = query_misses(TENANT, command="where", since_days=90, min_count=1)
        assert not misses

        # But a 365-day window SHOULD include it
        misses_wide = query_misses(TENANT, command="where", since_days=365, min_count=1)
        assert any(m.key == "old_op" for m in misses_wide)


class TestScanEvents:
    def test_scan_event_written(self, isolated_home: Path) -> None:
        record_scan_event(TENANT, "no_hardcoded_secrets", finding_count=3, acted_on=False)
        rows = query_scan_effectiveness(TENANT, since_days=1)
        assert any(r.rule_id == "no_hardcoded_secrets" for r in rows)

    def test_acted_on_tracked(self, isolated_home: Path) -> None:
        record_scan_event(TENANT, "no_empty_catch", finding_count=2, acted_on=True)
        rows = query_scan_effectiveness(TENANT, since_days=1)
        row = next(r for r in rows if r.rule_id == "no_empty_catch")
        assert row.acted_on_count == 1

    def test_effectiveness_aggregates(self, isolated_home: Path) -> None:
        for i in range(5):
            record_scan_event(TENANT, "my_rule", finding_count=i, acted_on=(i > 2))
        rows = query_scan_effectiveness(TENANT, since_days=1)
        row = next(r for r in rows if r.rule_id == "my_rule")
        assert row.run_count == 5
        assert row.total_findings == sum(range(5))
        assert row.acted_on_count == 2   # i=3 and i=4


class TestPurge:
    def test_old_events_are_deleted(self, isolated_home: Path) -> None:
        import time
        from unittest.mock import patch

        old_ts = int(time.time()) - 200 * 86_400
        with patch("onboarded_feedback.telemetry.store.time") as mock_time:
            mock_time.time.return_value = float(old_ts)
            for _ in range(10):
                record_event(TelemetryEvent("command", TENANT, "where", key="b", result="hit"))

        deleted = purge_old_events(TENANT, keep_days=100)
        assert deleted == 10
        summary = query_summary(TENANT, since_days=365)
        assert summary.total_events == 0

    def test_recent_events_are_kept(self, isolated_home: Path) -> None:
        record_event(TelemetryEvent("command", TENANT, "where", key="b", result="hit"))
        deleted = purge_old_events(TENANT, keep_days=365)
        assert deleted == 0
        summary = query_summary(TENANT, since_days=2)
        assert summary.total_events == 1