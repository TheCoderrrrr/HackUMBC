"""Users' own numbers: building a profile from the form, storing it under an anonymous key,
and owner-scoped saved plans."""
from __future__ import annotations

import hashlib
from datetime import date

import pytest
from fastapi.testclient import TestClient

from app import engine_port as engine
from app.ai.prompts import PROMPT_VERSION
from app.config import Settings
from app.main import create_app
from app.profile_builder import EMPLOYEE_LIMIT_CENTS, ProfileInput, build_profile, preview_state

from tests.test_history import FakeHistoryStore

KEY_A = "a" * 43
KEY_B = "b" * 43


def morgan():
    return next(p for p in engine.load_demo_profiles() if p.id == "morgan")


def morgan_form() -> dict:
    """Morgan's fixture numbers, typed into the form."""
    m = morgan()
    tier = m.employer_match.tiers[0]
    return {
        "name": "Morgan", "age": m.age, "retirement_age": m.retirement_age,
        "annual_gross_salary_cents": m.annual_gross_salary_cents, "monthly_take_home_cents": m.monthly_take_home_cents,
        "monthly_living_expenses_cents": m.monthly_living_expenses_cents,
        "employee_contribution_rate": m.employee_contribution_rate, "retirement_balance_cents": m.retirement_balance_cents,
        "emergency_cash_cents": m.emergency_cash_cents,
        "match": {"kind": "match", "up_to_rate": tier.employee_rate_to, "match_per_dollar": tier.match_per_employee_dollar},
        "debts": [{k: d[k] for k in ("type", "balance_cents", "apr", "minimum_payment_cents")} for d in
                  (x.model_dump() for x in m.debts)],
        "contribution_tax_treatment": m.contribution_tax_treatment,
        "estimated_marginal_income_tax_rate": m.estimated_marginal_income_tax_rate,
        "fund_id": m.fund_id, "fund_balance_confirmed": True,
        "fund_account_type": m.fund_account_type, "plan_menu_fund_ids": m.plan_menu_fund_ids,
    }


def rules_projection(profile):
    decision = engine.validate_decision(profile, engine.derive_state(profile), None, prompt_version=PROMPT_VERSION)
    return engine.evaluate(profile, None, decision).projections


@pytest.fixture
def store():
    return FakeHistoryStore()


@pytest.fixture
def client(store):
    return TestClient(create_app(Settings(ai_enabled=False), history=store))


# --- building ---------------------------------------------------------------------------


def test_morgans_numbers_typed_into_the_form_give_morgans_exact_plan():
    built = build_profile(ProfileInput.model_validate(morgan_form()), today=morgan().as_of_date)
    assert built.source == "manual" and built.id == "me"
    assert built.annual_employee_limit_cents == EMPLOYEE_LIMIT_CENTS == morgan().annual_employee_limit_cents
    mine, fixture = rules_projection(built), rules_projection(morgan())
    for strategy in ("current", "adaptive"):
        assert getattr(mine, strategy).points == getattr(fixture, strategy).points
        assert getattr(mine, strategy).debt_free_month == getattr(fixture, strategy).debt_free_month


def test_entered_fields_are_marked_user_confirmed():
    built = build_profile(ProfileInput.model_validate(morgan_form()))
    assert built.provenance["annual_gross_salary_cents"].source == "user_confirmed"
    assert built.provenance["annual_employee_limit_cents"].source == "fixture"  # a model default, not user input
    assert built.as_of_date == date.today()


def test_preview_is_the_engines_own_state():
    built = build_profile(ProfileInput.model_validate(morgan_form()))
    preview, blocking = preview_state(built)
    state = engine.derive_state(built)
    assert preview.emergency_months == state["emergency_months"]
    assert preview.employee_rate_for_full_match == 0.05 and blocking is None


@pytest.mark.parametrize("kind", ["none", "unknown"])
def test_no_or_unknown_match(kind):
    form = morgan_form() | {"match": {"kind": kind}}
    built = build_profile(ProfileInput.model_validate(form))
    assert built.employer_match.status == kind and built.employer_match.tiers == []
    _, blocking = preview_state(built)
    assert (blocking is not None) == (kind == "unknown")  # unknown matching is a documented blocked input


@pytest.mark.parametrize("change,field", [
    ({"retirement_age": 30}, "retirement_age"),
    ({"employee_contribution_rate": 0.9}, "employee_contribution_rate"),
    ({"debts": [{"type": "credit_card", "balance_cents": 100_000, "apr": 0.2, "minimum_payment_cents": 0}]},
     "debts.0.minimum_payment_cents"),
    ({"match": {"kind": "match"}}, "match"),
])
def test_invalid_numbers_point_at_the_form_field(client, change, field):
    res = client.post("/v1/profiles/build", json=morgan_form() | change)
    assert res.status_code == 422, res.text
    assert any(p == field or p.startswith(field) for p in res.json()["error"]["field_paths"]), res.json()


def test_build_endpoint_and_evaluate_accept_a_manual_profile(client):
    res = client.post("/v1/profiles/build", json=morgan_form())
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["profile"]["source"] == "manual" and body["preview"]["months_until_retirement"] == 32 * 12
    evaluation = client.post("/v1/evaluate", json={"profile": body["profile"]})
    assert evaluation.status_code == 200 and evaluation.json()["profile_id"] == "me"


# --- storing people's numbers under an anonymous key --------------------------------------

H = lambda key: {"x-profile-key": key}
OWNER_A = hashlib.sha256(KEY_A.encode()).hexdigest()


def _create(client, key=KEY_A, **change):
    res = client.post("/v1/profiles", json=morgan_form() | change, headers=H(key))
    assert res.status_code == 201, res.text
    return res.json()["profile"]


def test_add_several_people_load_update_and_erase(client, store):
    assert client.post("/v1/profiles", json=morgan_form()).status_code == 401  # no key
    assert client.post("/v1/profiles", json=morgan_form(), headers=H("short")).status_code == 422

    first, second = _create(client, name="Alex"), _create(client, name="Sam", age=28)
    assert first["id"] != second["id"] and first["id"].startswith("u-") and len(first["id"]) == 10
    # Only the key's hash is stored, never the key.
    assert {o for o, _ in store.profiles} == {OWNER_A}

    listed = client.get("/v1/profiles", headers=H(KEY_A)).json()["profiles"]
    assert [p["profile"]["name"] for p in listed] == ["Alex", "Sam"]
    assert client.get("/v1/profiles", headers=H(KEY_B)).json()["profiles"] == []

    updated = client.put(f"/v1/profiles/{second['id']}", json=morgan_form() | {"name": "Sam", "age": 29}, headers=H(KEY_A))
    assert updated.status_code == 200 and updated.json()["profile"]["age"] == 29
    assert client.get(f"/v1/profiles/{second['id']}", headers=H(KEY_A)).json()["form"]["age"] == 29
    assert client.get(f"/v1/profiles/{second['id']}", headers=H(KEY_B)).status_code == 404
    assert client.put(f"/v1/profiles/{second['id']}", json=morgan_form(), headers=H(KEY_B)).status_code == 404

    assert client.delete(f"/v1/profiles/{first['id']}", headers=H(KEY_A)).status_code == 204
    assert [p["profile"]["name"] for p in client.get("/v1/profiles", headers=H(KEY_A)).json()["profiles"]] == ["Sam"]


def test_profile_ids_are_validated(client):
    assert client.get("/v1/profiles/not-an-id", headers=H(KEY_A)).status_code == 422
    assert client.delete("/v1/profiles/u-XYZ", headers=H(KEY_A)).status_code == 422


def test_up_to_ten_people_per_key(client):
    for _ in range(10):
        _create(client)
    res = client.post("/v1/profiles", json=morgan_form(), headers=H(KEY_A))
    assert res.status_code == 409 and res.json()["error"]["code"] == "PROFILE_LIMIT"


def test_invalid_numbers_are_never_stored(client, store):
    res = client.post("/v1/profiles", json=morgan_form() | {"retirement_age": 30}, headers=H(KEY_A))
    assert res.status_code == 422 and store.profiles == {}


def test_storage_needs_the_database():
    client = TestClient(create_app(Settings(ai_enabled=False), history=None))
    res = client.post("/v1/profiles", json=morgan_form(), headers=H(KEY_A))
    assert res.status_code == 503 and res.json()["error"]["code"] == "HISTORY_DISABLED"


# --- plans saved from a person's numbers belong to that key ---------------------------------


def _save_plan(client, key, profile):
    evaluation = client.post("/v1/evaluate", json={"profile": profile}).json()
    return client.post("/v1/history/runs", headers=H(key), json={
        "profile_id": profile["id"], "scenario": None, "decision_summary": evaluation["decision_summary"],
        "input_hash": evaluation["input_hash"]})


def test_plans_are_private_to_the_key(client, store):
    profile = _create(client)
    mine = _save_plan(client, KEY_A, profile)
    assert mine.status_code == 201, mine.text
    run_id = mine.json()["run"]["run_id"]
    assert store.records[run_id].owner == OWNER_A and store.records[run_id].profile_id == profile["id"]

    listed = lambda key: client.get("/v1/history/runs", params={"profile_id": profile["id"]}, headers=H(key))
    assert [r["run_id"] for r in listed(KEY_A).json()["runs"]] == [run_id]
    assert listed(KEY_B).json()["runs"] == []
    assert client.get("/v1/history/runs", params={"profile_id": profile["id"]}).status_code == 401
    assert client.delete(f"/v1/history/runs/{run_id}", headers=H(KEY_B)).status_code == 404
    assert client.delete(f"/v1/history/runs/{run_id}").status_code == 404
    assert run_id in store.records


def test_saving_a_plan_needs_that_persons_saved_numbers(client):
    profile = _create(client)
    res = _save_plan(client, KEY_B, profile)  # another key can't save plans for this person
    assert res.status_code == 404 and res.json()["error"]["code"] == "PROFILE_NOT_FOUND"


def test_erasing_a_person_erases_only_their_plans(client, store):
    alex, sam = _create(client, name="Alex"), _create(client, name="Sam")
    _save_plan(client, KEY_A, alex)
    _save_plan(client, KEY_A, sam)
    assert client.delete(f"/v1/profiles/{alex['id']}", headers=H(KEY_A)).status_code == 204
    assert {r.profile_id for r in store.records.values()} == {sam["id"]}
