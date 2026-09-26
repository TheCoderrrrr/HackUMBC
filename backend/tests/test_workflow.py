"""Developer A workflow: circuit breaker, deadlines, scenarios, config, single state derivation."""
from __future__ import annotations

import pytest

from app import engine_port as engine
from app.ai.breaker import AIBreaker
from app.ai.client import AIRateLimited, AITimeout, GeminiModel, _retry_after
from app.ai.prompts import ExplanationOut, RecommendationOut, recommendation_schema

from .conftest import FakeModel, make_client, recommendation

BALANCED = ["starter_reserve", "high_apr_debt", "full_reserve"]


def post(client, profile, **extra):
    return client.post("/v1/evaluate", json={"profile": profile, **extra})


# --- circuit breaker ------------------------------------------------------------------


def test_breaker_opens_after_consecutive_timeouts_and_closes_after_cooldown():
    now = {"t": 0.0}
    b = AIBreaker(timeout_threshold=2, timeout_cooldown_s=30, clock=lambda: now["t"])
    b.record_timeout()
    assert not b.is_open()
    b.record_timeout()
    assert b.is_open()
    now["t"] = 31
    assert not b.is_open()


def test_success_resets_timeout_count():
    b = AIBreaker(timeout_threshold=2)
    b.record_timeout()
    b.record_success()
    b.record_timeout()
    assert not b.is_open()


def test_rate_limit_uses_provider_retry_after():
    now = {"t": 0.0}
    b = AIBreaker(rate_limit_cooldown_s=30, clock=lambda: now["t"])
    b.record_rate_limited(12.5)
    assert b.is_open() and b.remaining_s() == 12.5


def test_repeated_timeouts_skip_the_provider(morgan):
    model = FakeModel(recommend=AITimeout())
    client = make_client(model)
    reasons = [post(client, morgan).json()["decision_summary"]["fallback_reason"] for _ in range(3)]
    assert reasons == ["TIMEOUT", "TIMEOUT", "AI_COOLDOWN"]
    assert model.calls == [RecommendationOut, RecommendationOut]  # third request never called Gemini


def test_rate_limit_falls_back_and_cools_down(morgan):
    model = FakeModel(recommend=AIRateLimited(20.0))
    client = make_client(model)
    first = post(client, morgan).json()["decision_summary"]
    second = post(client, morgan).json()["decision_summary"]
    assert first["fallback_reason"] == "RATE_LIMITED" and first["source"] == "rules_fallback"
    assert second["fallback_reason"] == "AI_COOLDOWN"
    assert len(model.calls) == 1


def test_client_classifies_429_and_parses_retry_delay():
    assert _retry_after("Quota exceeded... Please retry in 20.366s.") == pytest.approx(20.366)
    assert _retry_after("no hint") is None

    class Quota(Exception):
        code = 429

    model = GeminiModel(api_key="test-key-not-used", model_id="gemini-test")

    def boom(*_):
        raise Quota("Please retry in 7s.")

    model._call = boom
    with pytest.raises(AIRateLimited) as info:
        model.generate("s", "p", ExplanationOut, timeout_s=2)
    assert info.value.retry_after_s == 7


# --- deadline --------------------------------------------------------------------------


def test_explanation_skipped_when_too_little_time_left(morgan):
    clock = {"t": 0.0}

    def slow(prompt):
        clock["t"] += 3.5  # leaves 0.5s, below the 0.8s floor
        return recommendation(BALANCED)

    model = FakeModel(recommend=slow)
    client = make_client(model)
    client.app.state.pipeline.clock = lambda: clock["t"]
    body = post(client, morgan).json()
    assert body["decision_summary"]["source"] == "ai"
    assert body["explanation"]["source"] == "template"
    assert model.calls == [RecommendationOut]


# --- custom scenarios ---------------------------------------------------------------------


def test_unaffordable_custom_election_is_infeasible(morgan):
    morgan["monthly_take_home_cents"] = 400000  # little room left after essentials and the card minimum
    res = post(make_client(), morgan, scenario={"retirement_age": 67, "employee_contribution_rate": 0.25})
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "INFEASIBLE_SCENARIO"
    assert err["field_paths"] == ["scenario.employee_contribution_rate"]
    assert "more per month" in err["message"]


def test_custom_election_above_annual_cap_is_infeasible(morgan):
    res = post(make_client(), morgan, scenario={"retirement_age": 67, "employee_contribution_rate": 0.5})
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "INFEASIBLE_SCENARIO"


def test_affordable_custom_election_is_accepted(morgan):
    res = post(make_client(), morgan, scenario={"retirement_age": 67, "employee_contribution_rate": 0.19})
    assert res.status_code == 200


def test_adaptive_scenario_without_rate_is_accepted(morgan):
    res = post(make_client(), morgan, scenario={"retirement_age": 69, "employee_contribution_rate": None})
    assert res.status_code == 200


# --- efficiency -------------------------------------------------------------------------------


def test_state_is_derived_once_per_request(morgan, monkeypatch):
    calls = {"n": 0}
    real = engine.derive_state

    def counting(profile):
        calls["n"] += 1
        return real(profile)

    monkeypatch.setattr(engine, "derive_state", counting)
    post(make_client(FakeModel()), morgan)
    assert calls["n"] == 1


def test_recommendation_schema_is_cached():
    keys = ["debt_burden", "financial_state.highest_debt_apr"]
    assert recommendation_schema(keys) is recommendation_schema(list(keys))


# --- configuration ------------------------------------------------------------------------------


@pytest.mark.parametrize("name,value", [
    ("AI_TOTAL_TIMEOUT_SECONDS", "abc"),
    ("AI_TOTAL_TIMEOUT_SECONDS", "30"),       # would exceed the iOS timeout
    ("AI_THINKING_LEVEL", "maximum"),
    ("AI_ENABLED", "maybe"),
    ("SESSION_TTL_SECONDS", "-5"),
    ("PLAID_ENABLED", "true"),
])
def test_bad_environment_values_stop_with_clear_message(monkeypatch, name, value):
    from app.config import ConfigError, load_settings
    monkeypatch.setenv(name, value)
    with pytest.raises(ConfigError) as info:
        load_settings()
    assert "Config error" in str(info.value) and name in str(info.value)


def test_thinking_level_parsing(monkeypatch):
    from app.config import load_settings
    for raw, expected in (("", "minimal"), ("LOW", "low"), ("none", None)):
        monkeypatch.setenv("AI_THINKING_LEVEL", raw)
        assert load_settings().ai_thinking_level == expected
