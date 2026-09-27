"""Scenario history: rebuilding runs, date and yearly rules shared with the app, and the API.

The database is replaced by FakeHistoryStore, whose yearly() follows the same rule as the
Tiger Data continuous aggregate (service.yearly_reference). test_history_tiger.py checks the
real aggregate against that rule.
"""
from __future__ import annotations

import copy
import json
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import engine_port as engine
from app.analytics import service
from app.analytics.models import RunRecord, RunSummary, YearRow
from app.analytics.store import HistoryUnavailable
from app.config import Settings
from app.main import create_app
from app.schemas import DecisionSummary, Scenario

GENERATED = Path(__file__).resolve().parents[1] / "fixtures" / "generated"
RULES = Settings(ai_enabled=False)


class FakeHistoryStore:
    """In-memory stand-in for TigerHistoryStore with the same contract."""

    def __init__(self):
        self.records: dict[str, RunRecord] = {}
        self.created: dict[str, datetime] = {}
        self.down = False
        self._clock = datetime(2026, 9, 27, tzinfo=timezone.utc)

    def _check(self):
        if self.down:
            raise HistoryUnavailable()

    def _summary(self, r: RunRecord) -> RunSummary:
        return RunSummary(
            run_id=r.run_id, profile_id=r.profile_id, label=r.label, created_at=self.created[r.run_id],
            as_of_date=r.as_of_date, scenario=r.scenario, primary_strategy=r.primary_strategy,
            retirement_age=r.retirement_age, final_retirement_balance_cents=r.final_retirement_balance_cents,
            decision_source=r.decision_source, model_id=r.model_id, prompt_version=r.prompt_version,
            model_version=r.model_version, policy_version=r.policy_version, input_hash=r.input_hash,
        )

    def ping(self):
        return not self.down

    def save(self, record):
        self._check()
        for existing in self.records.values():
            if existing.input_hash == record.input_hash:
                return self._summary(existing), False
        self._clock += timedelta(seconds=1)
        self.records[record.run_id], self.created[record.run_id] = record, self._clock
        return self._summary(record), True

    def list_runs(self, profile_id, limit):
        self._check()
        runs = [self._summary(r) for r in self.records.values() if r.profile_id == profile_id]
        return sorted(runs, key=lambda s: s.created_at, reverse=True)[:limit]

    def get_runs(self, run_ids):
        self._check()
        return {i: self._summary(self.records[i]) for i in run_ids if i in self.records}

    def yearly(self, pairs):
        self._check()
        return {i: service.yearly_reference(i, self.records[i].points, s) for i, s in pairs}


# --- helpers ---------------------------------------------------------------------


def profile(pid):
    return next(p for p in engine.load_demo_profiles() if p.id == pid)


def live_evaluation(client, pid, scenario=None):
    body = {"profile": profile(pid).model_dump(mode="json"), "scenario": scenario}
    res = client.post("/v1/evaluate", json=body)
    assert res.status_code == 200, res.text
    return res.json()


def save_body(evaluation, scenario=None):
    return {"profile_id": evaluation["profile_id"], "scenario": scenario,
            "decision_summary": evaluation["decision_summary"], "input_hash": evaluation["input_hash"]}


def balance_at_year(points, year):
    """Port of desktop/src/data/display.ts balanceAtYear: last point with month <= 12 * year."""
    value = points[0]["retirement_balance_cents"] if points else 0
    for p in points:
        if p["month"] <= year * 12:
            value = p["retirement_balance_cents"]
        else:
            break
    return value


def month_label(as_of: str, month: int) -> tuple[int, int]:
    """Port of desktop/src/data/format.ts monthLabel, as (year, month number)."""
    year, mon = int(as_of[:4]), int(as_of[5:7])
    absolute = mon - 1 + month
    return year + absolute // 12, absolute % 12 + 1


@pytest.fixture
def store():
    return FakeHistoryStore()


@pytest.fixture
def client(store):
    return TestClient(create_app(RULES, history=store))


# --- shared rules with the app ---------------------------------------------------------


@pytest.mark.parametrize("as_of", ["2026-09-26", "2026-01-31", "2026-12-01"])
@pytest.mark.parametrize("month", [0, 1, 3, 11, 12, 13, 250, 384])
def test_projected_date_matches_app_month_label(as_of, month):
    d = service.projected_date(date.fromisoformat(as_of), month)
    assert (d.year, d.month) == month_label(as_of, month) and d.day == 1


@pytest.mark.parametrize("pid", ["jordan", "morgan", "casey"])
def test_yearly_roll_up_matches_app_chart_sampling(client, pid):
    evaluation = live_evaluation(client, pid)
    record = service.build_run(pid, None, DecisionSummary.model_validate(evaluation["decision_summary"]),
                               evaluation["input_hash"])
    for strategy in ("current", "adaptive"):
        points = evaluation["projections"][strategy]["points"]
        rows = service.yearly_reference(record.run_id, record.points, strategy)
        years = points[-1]["month"] // 12
        assert [r.month for r in rows] == [12 * y for y in range(years + 1)]
        assert [r.retirement_balance_cents for r in rows] == [balance_at_year(points, y) for y in range(years + 1)]


# --- rebuilding a run from its inputs ------------------------------------------------------


@pytest.mark.parametrize("pid", ["jordan", "morgan", "casey"])
def test_rebuilt_run_equals_the_result_the_app_showed(client, pid):
    evaluation = live_evaluation(client, pid)
    record = service.build_run(pid, None, DecisionSummary.model_validate(evaluation["decision_summary"]),
                               evaluation["input_hash"])
    assert record.input_hash == evaluation["input_hash"]
    assert record.primary_strategy == "adaptive" and record.label == "Plan as is"
    assert record.final_retirement_balance_cents == evaluation["projections"]["adaptive"]["retirement_balance_nominal_cents"]
    for strategy in ("current", "adaptive"):
        stored = [(p.month, p.retirement_balance_cents, p.cash_cents, p.debt_cents)
                  for p in record.points if p.strategy == strategy]
        shown = [(p["month"], p["retirement_balance_cents"], p["cash_cents"], p["debt_cents"])
                 for p in evaluation["projections"][strategy]["points"]]
        assert stored == shown
    assert not any(p.strategy == "custom" for p in record.points)


def test_custom_scenario_run_stores_the_custom_projection(client):
    scenario = {"retirement_age": profile("casey").retirement_age + 2, "employee_contribution_rate": None}
    evaluation = live_evaluation(client, "casey", scenario)
    record = service.build_run("casey", Scenario.model_validate(scenario),
                               DecisionSummary.model_validate(evaluation["decision_summary"]), evaluation["input_hash"])
    assert record.primary_strategy == "custom"
    assert record.label == f"Retire at {scenario['retirement_age']} · adaptive contribution"
    custom = [(p.month, p.retirement_balance_cents) for p in record.points if p.strategy == "custom"]
    assert custom == [(p["month"], p["retirement_balance_cents"]) for p in evaluation["projections"]["custom"]["points"]]


@pytest.mark.parametrize("name", ["morgan-original", "casey-retire-plus-two", "jordan-contribution-plus-one"])
def test_saved_ai_results_from_the_offline_bundle_rebuild_exactly(name):
    artifact = json.loads((GENERATED / f"{name}.json").read_text(encoding="utf-8"))
    evaluation, scenario = artifact["evaluation"], artifact["scenario"]
    assert evaluation["decision_summary"]["source"] == "ai"
    record = service.build_run(evaluation["profile_id"], Scenario.model_validate(scenario) if scenario else None,
                               DecisionSummary.model_validate(evaluation["decision_summary"]), evaluation["input_hash"])
    assert record.decision_source == "ai" and record.model_id == evaluation["decision_summary"]["model_id"]
    strategy = "custom" if scenario else "adaptive"
    assert [(p.month, p.retirement_balance_cents) for p in record.points if p.strategy == strategy] == \
        [(p["month"], p["retirement_balance_cents"]) for p in evaluation["projections"][strategy]["points"]]


def test_stale_hash_is_rejected(client):
    evaluation = live_evaluation(client, "morgan")
    with pytest.raises(Exception) as err:
        service.build_run("morgan", None, DecisionSummary.model_validate(evaluation["decision_summary"]), "0" * 64)
    assert getattr(err.value, "code", None) == "STALE_RESULT" and err.value.status == 409


def test_a_rules_decision_with_a_different_order_is_rejected(client):
    evaluation = live_evaluation(client, "morgan")
    decision = copy.deepcopy(evaluation["decision_summary"])
    assert decision["source"] == "rules_fallback"
    decision["ordered_priorities"] = ["starter_reserve", "full_reserve", "high_apr_debt"]
    assert decision["ordered_priorities"] != evaluation["decision_summary"]["ordered_priorities"]
    with pytest.raises(Exception) as err:
        service.build_run("morgan", None, DecisionSummary.model_validate(decision), evaluation["input_hash"])
    assert err.value.code == "INVALID_REQUEST" and err.value.field_paths == ["decision_summary"]


def test_an_ai_decision_that_fails_the_validator_is_rejected():
    artifact = json.loads((GENERATED / "morgan-original.json").read_text(encoding="utf-8"))
    decision = copy.deepcopy(artifact["evaluation"]["decision_summary"])
    decision["rationale"][0]["summary"] = "Pay 25% of the card first."  # numbers are not allowed in rationale
    with pytest.raises(Exception) as err:
        service.build_run("morgan", None, DecisionSummary.model_validate(decision), artifact["evaluation"]["input_hash"])
    assert err.value.code == "INVALID_REQUEST"


def test_only_demo_profiles_can_be_saved(client):
    evaluation = live_evaluation(client, "morgan")
    with pytest.raises(Exception) as err:
        service.build_run("someone-else", None, DecisionSummary.model_validate(evaluation["decision_summary"]),
                          evaluation["input_hash"])
    assert err.value.code == "INVALID_REQUEST" and err.value.field_paths == ["profile_id"]


# --- API -------------------------------------------------------------------------


def test_save_is_idempotent(client, store):
    evaluation = live_evaluation(client, "morgan")
    first = client.post("/v1/history/runs", json=save_body(evaluation))
    again = client.post("/v1/history/runs", json=save_body(evaluation))
    assert first.status_code == 201 and first.json()["created"] is True
    assert again.status_code == 200 and again.json()["created"] is False
    assert again.json()["run"]["run_id"] == first.json()["run"]["run_id"]
    assert len(store.records) == 1


def test_list_is_per_profile_and_newest_first(client):
    morgan = live_evaluation(client, "morgan")
    scenario = {"retirement_age": profile("morgan").retirement_age + 2, "employee_contribution_rate": None}
    later = live_evaluation(client, "morgan", scenario)
    client.post("/v1/history/runs", json=save_body(morgan))
    client.post("/v1/history/runs", json=save_body(later, scenario))
    client.post("/v1/history/runs", json=save_body(live_evaluation(client, "jordan")))
    runs = client.get("/v1/history/runs", params={"profile_id": "morgan"}).json()["runs"]
    assert [r["label"] for r in runs] == [f"Retire at {scenario['retirement_age']} · adaptive contribution", "Plan as is"]
    assert all(r["profile_id"] == "morgan" for r in runs)


def test_compare_two_runs_over_time(client):
    base_eval = live_evaluation(client, "morgan")
    scenario = {"retirement_age": profile("morgan").retirement_age + 2, "employee_contribution_rate": None}
    other_eval = live_evaluation(client, "morgan", scenario)
    base = client.post("/v1/history/runs", json=save_body(base_eval)).json()["run"]
    other = client.post("/v1/history/runs", json=save_body(other_eval, scenario)).json()["run"]

    res = client.get("/v1/history/compare", params={"base": base["run_id"], "other": other["run_id"]})
    assert res.status_code == 200, res.text
    body = res.json()
    base_points = base_eval["projections"]["adaptive"]["points"]
    other_points = other_eval["projections"]["custom"]["points"]
    assert [y["year"] for y in body["years"]] == list(range(other_points[-1]["month"] // 12 + 1))
    for y in body["years"]:
        assert y["month"] == 12 * y["year"]
        assert tuple(int(x) for x in y["projected_on"].split("-")[:2]) == month_label(body["as_of_date"], y["month"])
        if y["base"] is not None:
            assert y["base"]["retirement_balance_cents"] == balance_at_year(base_points, y["year"])
        assert y["other"]["retirement_balance_cents"] == balance_at_year(other_points, y["year"])
    # The base plan retires two years earlier, so its last two years are empty.
    assert body["years"][-1]["base"] is None and body["years"][-1]["other"] is not None
    horizons = {h["years"]: h for h in body["horizons"]}
    assert set(horizons) == {5, 10, 20}
    assert horizons[10]["base"]["debt_cents"] == base_points[120]["debt_cents"]
    assert body["source"] == "tiger_data"


@pytest.mark.parametrize("params,status,code", [
    ({"base": "not-a-uuid", "other": "00000000-0000-0000-0000-000000000000"}, 422, "INVALID_REQUEST"),
    ({"base": "00000000-0000-0000-0000-000000000000", "other": "00000000-0000-0000-0000-000000000001"}, 404,
     "RUN_NOT_FOUND"),
])
def test_compare_rejects_bad_or_missing_runs(client, params, status, code):
    res = client.get("/v1/history/compare", params=params)
    assert res.status_code == status and res.json()["error"]["code"] == code


def test_compare_rejects_the_same_run_or_different_profiles(client):
    a = client.post("/v1/history/runs", json=save_body(live_evaluation(client, "morgan"))).json()["run"]["run_id"]
    b = client.post("/v1/history/runs", json=save_body(live_evaluation(client, "jordan"))).json()["run"]["run_id"]
    for other in (a, b):
        res = client.get("/v1/history/compare", params={"base": a, "other": other})
        assert res.status_code == 422 and res.json()["error"]["field_paths"] == ["other"]


def test_saving_an_unfundable_scenario_is_rejected(client, store):
    evaluation = live_evaluation(client, "morgan")
    scenario = {"retirement_age": profile("morgan").retirement_age, "employee_contribution_rate": 1.0}
    saved = client.post("/v1/history/runs", json=save_body(evaluation, scenario))
    assert saved.status_code == 422 and saved.json()["error"]["code"] == "INFEASIBLE_SCENARIO"
    assert store.records == {}


def test_history_disabled_without_a_database_url():
    client = TestClient(create_app(RULES, history=None))
    assert client.get("/v1/history/status").json() == {"enabled": False, "available": False}
    res = client.get("/v1/history/runs", params={"profile_id": "morgan"})
    assert res.status_code == 503 and res.json()["error"]["code"] == "HISTORY_DISABLED"
    assert client.post("/v1/evaluate", json={"profile": profile("morgan").model_dump(mode="json")}).status_code == 200


def test_database_outage_is_a_retryable_503_and_evaluate_still_works(client, store):
    evaluation = live_evaluation(client, "morgan")
    store.down = True
    assert client.get("/v1/history/status").json() == {"enabled": True, "available": False}
    for res in (client.post("/v1/history/runs", json=save_body(evaluation)),
                client.get("/v1/history/runs", params={"profile_id": "morgan"})):
        assert res.status_code == 503
        assert res.json()["error"] == {"code": "HISTORY_UNAVAILABLE", "retryable": True, "field_paths": [],
                                       "message": "Scenario history is unavailable right now. Try again."}
    assert live_evaluation(client, "morgan")["input_hash"] == evaluation["input_hash"]


def test_compare_rejects_rows_off_the_yearly_boundary():
    summary = RunSummary(run_id="a", profile_id="p", label="x", created_at=datetime.now(timezone.utc),
                         as_of_date=date(2026, 9, 1), scenario=None, primary_strategy="adaptive", retirement_age=67,
                         final_retirement_balance_cents=1, decision_source="rules_fallback", model_id=None,
                         prompt_version="2", model_version="1", policy_version="1", input_hash="h")
    other = summary.model_copy(update={"run_id": "b"})
    bad = [YearRow("a", "adaptive", 13, date(2027, 10, 1), 1, 1, 1)]
    with pytest.raises(ValueError):
        service.compare(summary, other, bad, [])
