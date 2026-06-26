"""
conftest.py — Shared pytest fixtures for the onboarded-feedback test suite.
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from onboarded_feedback.domain_loader import TenantDomainView, load_domain
from onboarded_feedback.telemetry.store import TelemetryEvent, record_event


FIXTURES_DIR = Path(__file__).parent / "fixtures"
SAMPLE_DOMAIN_PATH = FIXTURES_DIR / "sample_domain.json"


# ── Isolated home directory ───────────────────────────────────────────────────

@pytest.fixture()
def isolated_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """
    Redirect ~/.onboarded to a temp directory so tests never touch the
    real user home.  All telemetry and suggestions writes go here.
    """
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    monkeypatch.setenv("HOME", str(fake_home))
    # pathlib.Path.home() reads HOME env var on *nix — this is sufficient.
    return fake_home


# ── Domain fixture ────────────────────────────────────────────────────────────

@pytest.fixture()
def sample_domain(isolated_home: Path) -> TenantDomainView:
    """Load the shared sample domain.json as a TenantDomainView."""
    return load_domain("test", domain_root=FIXTURES_DIR)


@pytest.fixture()
def domain_path() -> Path:
    return SAMPLE_DOMAIN_PATH


# ── Telemetry seed helpers ────────────────────────────────────────────────────

def _seed_events(tenant: str, events: list[dict]) -> None:
    """Write a batch of telemetry events for a tenant."""
    for ev in events:
        record_event(TelemetryEvent(
            event_type=ev.get("event_type", "command"),
            tenant=tenant,
            command=ev["command"],
            key=ev.get("key"),
            result=ev.get("result", "hit"),
        ))


@pytest.fixture()
def seeded_misses(isolated_home: Path, sample_domain: TenantDomainView):
    """
    Seed the telemetry store with realistic miss events:
      - 'transfer'   ×12  genuine missing operation
      - 'resubmit'   ×7   genuine missing operation
      - 'bnd'        ×2   probable typo for 'bind'
      - 'paymet'     ×1   below MIN_MISS_COUNT, filtered out
    """
    events = (
        [{"command": "where", "key": "transfer",  "result": "miss", "event_type": "miss"}] * 12
        + [{"command": "where", "key": "resubmit", "result": "miss", "event_type": "miss"}] * 7
        + [{"command": "where", "key": "bnd",      "result": "miss", "event_type": "miss"}] * 2
        + [{"command": "where", "key": "paymet",   "result": "miss", "event_type": "miss"}] * 1
        + [{"command": "where", "key": "bind",     "result": "hit",  "event_type": "command"}] * 15
        + [{"command": "where", "key": "quote",    "result": "hit",  "event_type": "command"}] * 8
    )
    _seed_events("test", events)
    return sample_domain