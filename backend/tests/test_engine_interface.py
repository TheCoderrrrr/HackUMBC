"""Developer B names and values that Developers A and C rely on (DEVELOPER_A_NEEDS.md item 6).

A's prompt sends `recommendation_context` as the only allowed evidence and maps B's
fallback codes; C's simulator calls `allocate_month` every month. Changing anything
checked here breaks them, so this test fails first. Change these only after telling
Neil and Eric.
"""
from __future__ import annotations

import copy
import inspect
import json
from pathlib import Path

from app.engine import policy, state

PROFILES = Path(__file__).parents[1] / "fixtures" / "profiles.json"
KW = inspect.Parameter.KEYWORD_ONLY


def _morgan() -> dict:
    return next(p for p in json.loads(PROFILES.read_text(encoding="utf-8")) if p["id"] == "morgan")


def _params(fn) -> list[tuple[str, bool]]:
    return [(name, p.kind == KW) for name, p in inspect.signature(fn).parameters.items()]


def test_recommendation_context_keys_are_stable():
    profile = _morgan()
    context = state.recommendation_context(profile, state.derive_state(profile))
    assert sorted(k for k in context if k != "financial_state") == [
        "debt_burden", "emergency_cash_cents", "planning_preference", "savings_capacity"]
    assert sorted(context["financial_state"]) == [
        "critical_reserve_target_cents", "current_monthly_surplus_cents", "emergency_months",
        "employee_rate_for_full_match", "full_reserve_target_cents", "high_interest_debt_cents",
        "highest_debt_apr", "match_capture_fraction", "monthly_allocatable_budget_cents",
        "monthly_required_debt_payments_cents", "months_until_retirement", "starter_reserve_target_cents"]


def test_fallback_codes_used_by_the_api():
    profile = _morgan()
    no_proposal = policy.validate_decision(profile, state.derive_state(profile), None, prompt_version="2")
    assert no_proposal["fallback_reason"] == "NO_AI_PROPOSAL"  # engine_port maps it to A's reason

    blocked_profile = copy.deepcopy(profile)
    blocked_profile["employer_match"] = {"status": "unknown", "fully_vested": True, "tiers": []}
    blocked = policy.validate_decision(blocked_profile, state.derive_state(blocked_profile), None, prompt_version="2")
    assert blocked["fallback_reason"] == "BLOCKED_FINANCIAL_INPUT"  # pipeline keeps B's label


def test_documented_orders_are_stable():
    assert policy.PREFERENCE_ORDER == {
        "balanced": ("starter_reserve", "high_apr_debt", "full_reserve"),
        "cash_security": ("starter_reserve", "full_reserve", "high_apr_debt"),
        "debt_reduction": ("high_apr_debt", "starter_reserve", "full_reserve"),
    }
    assert policy.default_priorities("balanced") == policy.PREFERENCE_ORDER["balanced"]


def test_signatures_used_by_a_and_c():
    assert _params(state.derive_state) == [("profile", False)]
    assert _params(state.recommendation_context) == [("profile", False), ("state", False)]
    assert _params(policy.validate_decision) == [
        ("profile", False), ("state", False), ("proposal", False), ("model_id", True), ("prompt_version", True)]
    assert _params(policy.build_plan) == [("profile", False), ("state", False), ("decision", False)]
    assert _params(policy.allocate_month) == [
        ("profile", False), ("state", False), ("decision", False),
        ("month", True), ("strategy", True), ("employee_contribution_rate", True)]
