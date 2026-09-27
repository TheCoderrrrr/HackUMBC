"""Scenario history against a real Tiger Data service (skipped without TIGER_DATABASE_URL).

Each run uses a fresh schema and drops it afterwards. The key check: the continuous
aggregate returns exactly service.yearly_reference, the rule the desktop chart uses.
"""
from __future__ import annotations

import os
import uuid

import pytest
from fastapi.testclient import TestClient

from app import engine_port as engine
from app.analytics import service
from app.analytics.store import HistoryUnavailable, TigerHistoryStore
from app.config import Settings
from app.main import create_app
from app.schemas import DecisionSummary, Scenario

URL = os.getenv("TIGER_DATABASE_URL", "").strip()
RULES = Settings(ai_enabled=False)


def test_unreachable_database_reports_unavailable():
    store = TigerHistoryStore("postgresql://nobody@127.0.0.1:1/none", connect_timeout=2)
    assert store.ping() is False
    with pytest.raises(HistoryUnavailable):
        store.list_runs("morgan", 5)


needs_tiger = pytest.mark.skipif(not URL, reason="TIGER_DATABASE_URL is not set")


@pytest.fixture(scope="module")
def tiger():
    schema = f"arm_test_{uuid.uuid4().hex[:10]}"
    store = TigerHistoryStore(URL, schema)
    yield store
    store.close()
    import psycopg

    with psycopg.connect(URL, autocommit=True) as conn:
        conn.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")


def _record(pid, scenario=None):
    client = TestClient(create_app(RULES, history=None))
    profile = next(p for p in engine.load_demo_profiles() if p.id == pid)
    res = client.post("/v1/evaluate", json={"profile": profile.model_dump(mode="json"), "scenario": scenario})
    evaluation = res.json()
    record = service.build_run(pid, Scenario.model_validate(scenario) if scenario else None,
                               DecisionSummary.model_validate(evaluation["decision_summary"]), evaluation["input_hash"])
    return record, evaluation


@needs_tiger
def test_timescale_objects_exist(tiger):
    assert tiger.ping()
    import psycopg

    with psycopg.connect(URL) as conn:
        hyper = conn.execute("SELECT count(*) FROM timescaledb_information.hypertables "
                             "WHERE hypertable_schema = %s AND hypertable_name = 'projection_point'",
                             (tiger.schema,)).fetchone()[0]
        cagg = conn.execute("SELECT materialized_only FROM timescaledb_information.continuous_aggregates "
                            "WHERE view_schema = %s AND view_name = 'projection_yearly'", (tiger.schema,)).fetchone()
    assert hyper == 1 and cagg == (False,)
    with psycopg.connect(URL) as conn:
        compressed = conn.execute("SELECT compression_enabled FROM timescaledb_information.hypertables "
                                  "WHERE hypertable_schema = %s AND hypertable_name = 'projection_point'", (tiger.schema,)).fetchone()
        jobs = conn.execute("SELECT count(*) FROM timescaledb_information.jobs WHERE hypertable_schema = %s "
                            "AND proc_name = 'policy_compression'", (tiger.schema,)).fetchone()[0]
    assert compressed == (True,) and jobs == 1


@needs_tiger
def test_save_query_and_compare_on_tiger(tiger):
    base, base_eval = _record("morgan")
    scenario = {"retirement_age": base_eval["projections"]["adaptive"]["retirement_age"] + 2,
                "employee_contribution_rate": None}
    other, _ = _record("morgan", scenario)

    saved, created = tiger.save(base)
    again, created_again = tiger.save(base)
    assert created and not created_again and again.run_id == saved.run_id == base.run_id
    other_saved, _ = tiger.save(other)

    # Provenance survives the round trip.
    assert saved.input_hash == base_eval["input_hash"] and saved.label == "Plan as is"
    assert saved.model_version == base_eval["model_version"] and saved.decision_source == "rules_fallback"
    assert saved.final_retirement_balance_cents == base_eval["projections"]["adaptive"]["retirement_balance_nominal_cents"]

    # The continuous aggregate equals the app's yearly sampling, row for row.
    rows = tiger.yearly([(base.run_id, "adaptive"), (base.run_id, "current"), (other.run_id, "custom")])
    for run, strategy in ((base, "adaptive"), (base, "current"), (other, "custom")):
        got = [r for r in rows[run.run_id] if r.strategy == strategy] if strategy != "custom" else rows[run.run_id]
        assert got == service.yearly_reference(run.run_id, run.points, strategy)

    assert [r.run_id for r in tiger.list_runs("morgan", 10)] == [other_saved.run_id, saved.run_id]
    assert tiger.list_runs("jordan", 10) == []
    assert set(tiger.get_runs([base.run_id, str(uuid.uuid4())])) == {base.run_id}

    # Same comparison through the API with the real store.
    client = TestClient(create_app(RULES, history=tiger))
    res = client.get("/v1/history/compare", params={"base": base.run_id, "other": other.run_id})
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["horizons"][1]["base"]["debt_cents"] == base_eval["projections"]["adaptive"]["points"][120]["debt_cents"]


@needs_tiger
def test_delete_and_compressed_reads_on_tiger(tiger):
    record, _ = _record("casey")
    tiger.save(record)
    import psycopg

    with psycopg.connect(URL, autocommit=True) as conn:  # compress now, as the policy would, then read through it
        for (chunk,) in conn.execute("SELECT show_chunks(%s)", (f"{tiger.schema}.projection_point",)).fetchall():
            conn.execute("SELECT compress_chunk(%s, if_not_compressed => TRUE)", (chunk,))
    rows = tiger.yearly([(record.run_id, "adaptive")])[record.run_id]
    assert rows == service.yearly_reference(record.run_id, record.points, "adaptive")

    assert tiger.delete(record.run_id) is True
    assert tiger.delete(record.run_id) is False
    assert tiger.yearly([(record.run_id, "adaptive")])[record.run_id] == []
    assert record.run_id not in {r.run_id for r in tiger.list_runs("casey", 20)}


@needs_tiger
def test_pool_reuses_connections(tiger):
    for _ in range(5):
        assert tiger.ping()
    stats = tiger._get_pool().get_stats()
    assert "connections_num" in stats and stats["connections_num"] <= 2  # five calls, not five TLS handshakes



@needs_tiger
def test_user_profiles_and_owner_scoped_runs_on_tiger(tiger):
    import dataclasses
    import hashlib

    alice, bob = hashlib.sha256(b"alice-key").hexdigest(), hashlib.sha256(b"bob-key").hexdigest()
    record, _ = _record("jordan")

    # The profile table round-trips JSON and upserts.
    tiger.save_profile(alice, {"age": 35}, {"id": "me"})
    tiger.save_profile(alice, {"age": 36}, {"id": "me"})
    assert tiger.get_profile(alice) == ({"age": 36}, {"id": "me"})
    assert tiger.get_profile(bob) is None

    # The same plan saved by two owners is two private runs, and a shared demo run stays separate.
    mine = dataclasses.replace(record, run_id=str(uuid.uuid4()), profile_id="me", owner=alice)
    theirs = dataclasses.replace(record, run_id=str(uuid.uuid4()), profile_id="me", owner=bob)
    assert tiger.save(mine)[1] and tiger.save(theirs)[1]
    assert not tiger.save(dataclasses.replace(mine, run_id=str(uuid.uuid4())))[1]  # idempotent per owner
    assert [r.run_id for r in tiger.list_runs("me", 10, alice)] == [mine.run_id]
    assert set(tiger.get_runs([mine.run_id, theirs.run_id], alice)) == {mine.run_id}
    assert tiger.delete(theirs.run_id, alice) is False and tiger.delete(theirs.run_id) is False

    # Erasing a profile removes its runs, and only its runs.
    assert tiger.delete_profile(alice) is True
    assert tiger.list_runs("me", 10, alice) == [] and tiger.get_profile(alice) is None
    assert [r.run_id for r in tiger.list_runs("me", 10, bob)] == [theirs.run_id]
