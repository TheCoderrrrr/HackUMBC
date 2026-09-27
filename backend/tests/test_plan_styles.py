"""Plan-style comparison and style-aware history saves."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import engine_port as engine
from app.ai.prompts import PROMPT_VERSION
from app.config import Settings
from app.main import create_app
from app.plan_styles import STYLE_LABELS, STYLES, compare_styles

from tests.test_history import FakeHistoryStore, save_body


class NoAIModel:
    """Fails the test if the comparison ever calls a model."""

    model_id = "must-not-be-called"

    def generate(self, *args, **kwargs):
        raise AssertionError("plan-style comparison must not call the AI model")


def profile(pid):
    return next(p for p in engine.load_demo_profiles() if p.id == pid)


@pytest.fixture
def client():
    return TestClient(create_app(Settings(ai_enabled=True, gemini_api_key="x", ai_provider="gemini",
                                          ai_model="gemini-3.5-flash-lite"), model=NoAIModel(), history=None))


@pytest.mark.parametrize("pid", ["jordan", "morgan", "casey"])
def test_each_style_is_the_engine_run_with_that_styles_rule_order(pid):
    result = compare_styles(profile(pid))
    assert [s.style for s in result.styles] == list(STYLES)
    for outcome in result.styles:
        styled = profile(pid).model_copy(update={"planning_preference": outcome.style})
        assert outcome.ordered_priorities == engine.default_order(outcome.style)
        assert outcome.label == STYLE_LABELS[outcome.style]
        decision = engine.validate_decision(styled, engine.derive_state(styled), None, prompt_version=PROMPT_VERSION)
        points = engine.evaluate(styled, None, decision).projections.adaptive.points
        yearly = [(p.month, p.retirement_balance_cents, p.cash_cents, p.debt_cents) for p in points if p.month % 12 == 0]
        assert [(y.month, y.retirement_balance_cents, y.cash_cents, y.debt_cents) for y in outcome.yearly] == yearly
        assert [y.year for y in outcome.yearly] == [y.month // 12 for y in outcome.yearly]


@pytest.mark.parametrize("pid", ["jordan", "morgan", "casey"])
def test_current_habits_do_not_depend_on_the_style(pid):
    result = compare_styles(profile(pid))
    assert result.current.style is None and result.current.label == "Current habits"
    for style in STYLES:
        styled = profile(pid).model_copy(update={"planning_preference": style})
        decision = engine.validate_decision(styled, engine.derive_state(styled), None, prompt_version=PROMPT_VERSION)
        current = engine.evaluate(styled, None, decision).projections.current
        assert [(y.month, y.retirement_balance_cents) for y in result.current.yearly] == \
            [(p.month, p.retirement_balance_cents) for p in current.points if p.month % 12 == 0]


def test_styles_trade_debt_speed_against_cash_security_for_morgan():
    by_style = {s.style: s for s in compare_styles(profile("morgan")).styles}
    cash, debt = by_style["cash_security"], by_style["debt_reduction"]
    assert cash.full_reserve_month < debt.full_reserve_month          # cushion first
    assert debt.debt_free_month < cash.debt_free_month                # card first
    assert debt.cumulative_debt_interest_cents < cash.cumulative_debt_interest_cents


@pytest.mark.parametrize("pid", ["jordan", "casey"])
def test_styles_can_be_identical_when_there_is_nothing_to_trade_off(pid):
    styles = compare_styles(profile(pid)).styles
    assert len({(s.debt_free_month, s.full_reserve_month, s.retirement_balance_nominal_cents) for s in styles}) == 1


def test_api_returns_all_styles_without_calling_ai(client):
    res = client.post("/v1/plan-styles", json={"profile": profile("morgan").model_dump(mode="json")})
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["profile_id"] == "morgan" and [s["style"] for s in body["styles"]] == list(STYLES)
    assert body["current"]["label"] == "Current habits"


def test_api_rejects_an_invalid_profile(client):
    bad = profile("morgan").model_dump(mode="json") | {"monthly_living_expenses_cents": 0}
    res = client.post("/v1/plan-styles", json={"profile": bad})
    assert res.status_code == 422 and res.json()["error"]["code"] == "INVALID_PROFILE"


# --- history saves remember the style ------------------------------------------------------


@pytest.fixture
def rules_client():
    store = FakeHistoryStore()
    return TestClient(create_app(Settings(ai_enabled=False), history=store)), store


def test_saving_a_result_made_with_another_style_records_that_style(rules_client):
    client, store = rules_client
    styled = profile("morgan").model_dump(mode="json") | {"planning_preference": "cash_security"}
    evaluation = client.post("/v1/evaluate", json={"profile": styled}).json()

    # Without the style, the server rebuilds the decision with the fixture's (balanced) order,
    # which doesn't match the cash-security order the app showed.
    without = client.post("/v1/history/runs", json=save_body(evaluation))
    assert without.status_code == 422 and without.json()["error"]["field_paths"] == ["decision_summary"]

    saved = client.post("/v1/history/runs", json=save_body(evaluation) | {"planning_preference": "cash_security"})
    assert saved.status_code == 201, saved.text
    assert saved.json()["run"]["label"] == "Plan as is · Cash security first"
    assert saved.json()["run"]["input_hash"] == evaluation["input_hash"]


def test_default_style_keeps_the_plain_label(rules_client):
    client, _ = rules_client
    evaluation = client.post("/v1/evaluate", json={"profile": profile("morgan").model_dump(mode="json")}).json()
    saved = client.post("/v1/history/runs", json=save_body(evaluation) | {"planning_preference": "balanced"})
    assert saved.status_code == 201 and saved.json()["run"]["label"] == "Plan as is"
