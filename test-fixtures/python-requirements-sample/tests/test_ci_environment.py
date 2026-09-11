"""Proves what the CI template promises, rather than trusting it.

Both of these have already been wrong in this repo: the test job ran with no
database (seoforge-ai's whole suite silently skipped, 0 tests executed, 27%
coverage reported), and a pre-test hook that never fires would fail exactly the
same silent way.
"""
import os
from pathlib import Path

import pytest


def test_database_url_points_at_a_live_postgres():
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        pytest.skip("not running under the CI template")

    psycopg = pytest.importorskip("psycopg", reason="psycopg not installed")
    with psycopg.connect(dsn, connect_timeout=10) as conn:
        assert conn.execute("SELECT 1").fetchone() == (1,)


def test_pre_test_command_ran():
    if not os.environ.get("DATABASE_URL"):
        pytest.skip("not running under the CI template")

    marker = Path(__file__).resolve().parents[1] / "pre-test-ran.txt"
    assert marker.is_file(), (
        "pre-test-command did not run — the caller asked for it and nothing executed"
    )
    assert marker.read_text().strip() == "ok"
