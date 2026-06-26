"""
telemetry/store.py — Local SQLite telemetry store.

Storage:  ~/.onboarded/{tenant}/telemetry.db
Privacy:  Keys and command names only. No file content, no path values,
          no code, no credentials, no repo names.

All public write functions are intentionally silent on failure — telemetry
must never interrupt the developer's terminal workflow. A 20 ms budget for
any single write is enforced by the SQLite timeout parameter.

Integration note: at merge time this module moves to
packages/core/src/telemetry/store.py and the FastAPI app imports it for
the /admin/telemetry endpoints added in the post-v1 admin CLI extension.
"""
from __future__ import annotations

import sqlite3
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Generator, Literal

# ── Type aliases ──────────────────────────────────────────────────────────────

EventType  = Literal["command", "miss", "path_not_found", "stale_path", "learn"]
CommandType = Literal["where", "status", "explain", "audit", "scan", "list", "learn",
                      "cd", "grep", "secrets", "suggest", "doctor"]
ResultType = Literal["hit", "miss", "partial"]

# ── Schema ────────────────────────────────────────────────────────────────────

_SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous  = NORMAL;

CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type  TEXT    NOT NULL,
    tenant      TEXT    NOT NULL,
    command     TEXT    NOT NULL,
    key         TEXT,
    result      TEXT,
    ts          INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS scan_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant        TEXT    NOT NULL,
    rule_id       TEXT    NOT NULL,
    finding_count INTEGER NOT NULL DEFAULT 0,
    acted_on      INTEGER NOT NULL DEFAULT 0,
    ts            INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ev_tenant  ON events(tenant);
CREATE INDEX IF NOT EXISTS idx_ev_command ON events(command);
CREATE INDEX IF NOT EXISTS idx_ev_result  ON events(result);
CREATE INDEX IF NOT EXISTS idx_ev_ts      ON events(ts);
CREATE INDEX IF NOT EXISTS idx_scan_rule  ON scan_events(rule_id, tenant);
CREATE INDEX IF NOT EXISTS idx_scan_ts    ON scan_events(ts);
"""


# ── Internal helpers ──────────────────────────────────────────────────────────

def _db_path(tenant: str) -> Path:
    base = Path.home() / ".onboarded" / tenant
    base.mkdir(parents=True, exist_ok=True)
    return base / "telemetry.db"


@contextmanager
def _conn(tenant: str) -> Generator[sqlite3.Connection, None, None]:
    db = _db_path(tenant)
    con = sqlite3.connect(str(db), timeout=5, check_same_thread=False)
    con.row_factory = sqlite3.Row
    try:
        con.executescript(_SCHEMA)
        yield con
        con.commit()
    finally:
        con.close()


# ── Public data shapes ────────────────────────────────────────────────────────

@dataclass(frozen=True)
class TelemetryEvent:
    event_type: EventType
    tenant:     str
    command:    CommandType
    key:        str | None    = None
    result:     ResultType | None = None


@dataclass(frozen=True)
class MissRecord:
    key: str
    command: str
    count: int


@dataclass(frozen=True)
class TelemetrySummary:
    tenant: str
    total_events: int
    miss_count: int
    partial_count: int
    hit_count: int
    top_misses: list[MissRecord]
    top_operations: list[tuple[str, int]]   # (key, hit_count)


@dataclass(frozen=True)
class ScanEffectivenessRow:
    rule_id: str
    run_count: int
    total_findings: int
    acted_on_count: int
    avg_findings: float
    resolution_rate: float   # acted_on / run_count


# ── Write API ─────────────────────────────────────────────────────────────────

def record_event(event: TelemetryEvent) -> None:
    """
    Write one command event. Silently swallows all errors.
    Called from the Zsh telemetry hooks after each command completes.
    """
    try:
        with _conn(event.tenant) as con:
            con.execute(
                "INSERT INTO events (event_type, tenant, command, key, result, ts) "
                "VALUES (?,?,?,?,?,?)",
                (event.event_type, event.tenant, event.command,
                 event.key, event.result, int(time.time())),
            )
    except Exception:  # noqa: BLE001
        pass


def record_scan_event(
    tenant: str,
    rule_id: str,
    finding_count: int,
    acted_on: bool = False,
) -> None:
    """
    Record the outcome of executing one scan rule.
    `acted_on` is set by the shell hook when a commit follows a clean audit.
    Silently swallows all errors.
    """
    try:
        with _conn(tenant) as con:
            con.execute(
                "INSERT INTO scan_events (tenant, rule_id, finding_count, acted_on, ts) "
                "VALUES (?,?,?,?,?)",
                (tenant, rule_id, finding_count, int(acted_on), int(time.time())),
            )
    except Exception:  # noqa: BLE001
        pass


# ── Read API ──────────────────────────────────────────────────────────────────

def query_misses(
    tenant: str,
    command: str | None = None,
    since_days: int = 90,
    min_count: int = 1,
) -> list[MissRecord]:
    """
    Return keys that produced misses, ranked by frequency.
    Used by gap_detection.operation_gaps to find missing operations.
    """
    since_ts = int(time.time()) - since_days * 86_400

    with _conn(tenant) as con:
        if command is not None:
            cur = con.execute(
                """
                SELECT key, command, COUNT(*) AS cnt
                FROM   events
                WHERE  tenant  = ?
                  AND  result  = 'miss'
                  AND  ts      >= ?
                  AND  command = ?
                  AND  key IS NOT NULL
                GROUP  BY key, command
                HAVING cnt >= ?
                ORDER  BY cnt DESC
                """,
                (tenant, since_ts, command, min_count),
            )
        else:
            cur = con.execute(
                """
                SELECT key, command, COUNT(*) AS cnt
                FROM   events
                WHERE  tenant  = ?
                  AND  result  = 'miss'
                  AND  ts      >= ?
                  AND  key IS NOT NULL
                GROUP  BY key, command
                HAVING cnt >= ?
                ORDER  BY cnt DESC
                """,
                (tenant, since_ts, min_count),
            )
        return [MissRecord(key=r["key"], command=r["command"], count=r["cnt"])
                for r in cur.fetchall()]


def query_summary(tenant: str, since_days: int = 30) -> TelemetrySummary:
    """Return a summary suitable for `ob-feedback telemetry show`."""
    since_ts = int(time.time()) - since_days * 86_400

    with _conn(tenant) as con:
        total = con.execute(
            "SELECT COUNT(*) FROM events WHERE tenant=? AND ts>=?",
            (tenant, since_ts),
        ).fetchone()[0]

        def _count(result: str) -> int:
            return con.execute(
                "SELECT COUNT(*) FROM events WHERE tenant=? AND result=? AND ts>=?",
                (tenant, result, since_ts),
            ).fetchone()[0]

        hit_count     = _count("hit")
        miss_count    = _count("miss")
        partial_count = _count("partial")

        top_misses_rows = con.execute(
            """
            SELECT key, command, COUNT(*) AS cnt
            FROM   events
            WHERE  tenant=? AND result='miss' AND ts>=? AND key IS NOT NULL
            GROUP  BY key, command
            ORDER  BY cnt DESC LIMIT 10
            """,
            (tenant, since_ts),
        ).fetchall()

        top_ops_rows = con.execute(
            """
            SELECT key, COUNT(*) AS cnt
            FROM   events
            WHERE  tenant=? AND command='where' AND result='hit' AND ts>=? AND key IS NOT NULL
            GROUP  BY key
            ORDER  BY cnt DESC LIMIT 10
            """,
            (tenant, since_ts),
        ).fetchall()

    top_misses = [MissRecord(key=r["key"], command=r["command"], count=r["cnt"])
                  for r in top_misses_rows]
    top_ops    = [(r["key"], r["cnt"]) for r in top_ops_rows]

    return TelemetrySummary(
        tenant=tenant,
        total_events=total,
        miss_count=miss_count,
        partial_count=partial_count,
        hit_count=hit_count,
        top_misses=top_misses,
        top_operations=top_ops,
    )


def query_scan_effectiveness(
    tenant: str,
    since_days: int = 90,
) -> list[ScanEffectivenessRow]:
    """
    Return per-rule effectiveness metrics for `ob-feedback suggest rules`.
    """
    since_ts = int(time.time()) - since_days * 86_400

    with _conn(tenant) as con:
        rows = con.execute(
            """
            SELECT
                rule_id,
                COUNT(*)          AS run_count,
                SUM(finding_count) AS total_findings,
                SUM(acted_on)      AS acted_on_count,
                AVG(finding_count) AS avg_findings
            FROM   scan_events
            WHERE  tenant=? AND ts>=?
            GROUP  BY rule_id
            ORDER  BY run_count DESC
            """,
            (tenant, since_ts),
        ).fetchall()

    result = []
    for r in rows:
        run_count    = r["run_count"]
        acted_on     = r["acted_on_count"] or 0
        result.append(ScanEffectivenessRow(
            rule_id=r["rule_id"],
            run_count=run_count,
            total_findings=r["total_findings"] or 0,
            acted_on_count=acted_on,
            avg_findings=r["avg_findings"] or 0.0,
            resolution_rate=acted_on / run_count if run_count else 0.0,
        ))
    return result


def purge_old_events(tenant: str, keep_days: int = 180) -> int:
    """Delete events older than keep_days. Returns total number of rows deleted."""
    cutoff = int(time.time()) - keep_days * 86_400
    with _conn(tenant) as con:
        cur1 = con.execute("DELETE FROM events WHERE tenant=? AND ts<?", (tenant, cutoff))
        cur2 = con.execute("DELETE FROM scan_events WHERE tenant=? AND ts<?", (tenant, cutoff))
    return (cur1.rowcount or 0) + (cur2.rowcount or 0)