"""Decision boundaries and first-month adaptive cash allocation."""

from copy import deepcopy

import pytest

from app.engine.policy import PREFERENCE_ORDER, allocate_month, default_priorities, validate_decision
from app.engine.state import derive_state


def decision(profile, order=None):
    return {"ordered_priorities": list(order or default_priorities(profile.get("planning_preference", "balanced")))}


def proposal(profile, order=None):
    order = list(order or default_priorities(profile.get("planning_preference", "balanced")))
    return {"ordered_priorities": order, "rationale": [
        {"priority": key, "summary": "Grounded recommendation",
         "evidence_paths": ["financial_state.emergency_months"],
         "tradeoff": "Cash committed here cannot serve another priority."}
        for key in order]}


def alloc(profile, order=None):
    return allocate_month(profile, derive_state(profile), decision(profile, order))


def assert_cash_identity(result):
    assert result["resources_cents"] == (
        result["living_expenses_cents"]
        + sum(debt["total_payment_cents"] for debt in result["debts"])
        + result["employee_cash_cost_cents"] + result["total_cash_added_cents"]
    )
    assert all(0 <= debt["total_payment_cents"] <= debt["amount_due_cents"]
               and debt["closing_balance_cents"] >= 0 for debt in result["debts"])


def test_morgan_first_month_acceptance(morgan):
    original = deepcopy(morgan)
    result = alloc(morgan)
    assert result["feasible"]
    assert result["employee_contribution_cents"] == 35000
    assert result["employee_cash_cost_cents"] == 27300
    assert result["employer_match_cents"] == 35000
    assert result["debts"][0]["extra_payment_cents"] == 96380
    assert result["debts"][0]["total_payment_cents"] == 136380
    assert result["total_cash_added_cents"] == 0
    assert_cash_identity(result)
    assert morgan == original


@pytest.mark.parametrize("name", ["jordan", "casey"])
def test_established_profiles_keep_original_employee_rate(profiles, name):
    profile = deepcopy(profiles[name])
    result = alloc(profile)
    assert result["feasible"]
    assert result["employee_contribution_rate"] == pytest.approx(profile["employee_contribution_rate"])
    assert result["employee_contribution_cents"] == (100000 if name == "jordan" else 110000)
    assert result["employer_match_cents"] == (50000 if name == "jordan" else 45833)
    assert_cash_identity(result)


@pytest.mark.parametrize("preference,expected", [
    ("balanced", ["starter_reserve", "high_apr_debt", "full_reserve"]),
    ("cash_security", ["starter_reserve", "full_reserve", "high_apr_debt"]),
    ("debt_reduction", ["high_apr_debt", "starter_reserve", "full_reserve"]),
])
def test_preference_defaults_are_accepted_as_ai(morgan, preference, expected):
    morgan["planning_preference"] = preference
    state = derive_state(morgan)
    accepted = validate_decision(morgan, state, proposal(morgan), model_id="test-model", prompt_version="test-v1")
    assert accepted["source"] == "ai"
    assert accepted["ordered_priorities"] == expected
    assert accepted["model_id"] == "test-model"
    assert accepted["prompt_version"] == "test-v1"
    assert accepted["fallback_reason"] is None
    assert all(check["passed"] for check in accepted["constraint_checks"])


@pytest.mark.parametrize("order", list(PREFERENCE_ORDER.values()))
def test_any_documented_preference_order_is_a_valid_ai_choice(morgan, order):
    state = derive_state(morgan)
    accepted = validate_decision(
        morgan, state, proposal(morgan, order), model_id="test-model", prompt_version="test-v1",
    )
    assert accepted["source"] == "ai"
    assert accepted["ordered_priorities"] == list(order)
    assert accepted["fallback_reason"] is None


def test_cash_security_may_choose_debt_before_full_reserve(morgan):
    morgan["planning_preference"] = "cash_security"
    morgan["emergency_cash_cents"] += 1
    special = proposal(morgan, ["starter_reserve", "high_apr_debt", "full_reserve"])
    accepted = validate_decision(morgan, derive_state(morgan), special, model_id="m")
    assert accepted["source"] == "ai"
    assert accepted["ordered_priorities"] == ["starter_reserve", "high_apr_debt", "full_reserve"]
    morgan["emergency_cash_cents"] -= 1
    original = validate_decision(
        morgan, derive_state(morgan),
        proposal(morgan, ["starter_reserve", "high_apr_debt", "full_reserve"]),
        model_id="m",
    )
    allocated = allocate_month(morgan, derive_state(morgan), original)
    assert allocated["debts"][0]["extra_payment_cents"] == 96380


@pytest.mark.parametrize("change", [
    lambda p: p.update(ordered_priorities=["starter_reserve", "high_apr_debt"]),
    lambda p: p.update(ordered_priorities=["starter_reserve", "starter_reserve", "full_reserve"]),
    lambda p: p.update(ordered_priorities=["full_reserve", "high_apr_debt", "starter_reserve"]),
    lambda p: p.update(ordered_priorities=["starter_reserve", "alien", "full_reserve"]),
    lambda p: p.update(ordered_priorities=["starter_reserve", ["high_apr_debt"], "full_reserve"]),
    lambda p: p.update(ordered_priorities={"starter_reserve": 1}),
    lambda p: p.update(ordered_priorities=None),
    lambda p: p["rationale"][0].update(evidence_paths=["financial_state.unknown"]),
    lambda p: p["rationale"][0].update(evidence_paths=None),
    lambda p: p["rationale"][0].update(evidence_paths=[["financial_state.emergency_months"]]),
    lambda p: p["rationale"][0].update(evidence_paths=["financial_state.emergency_months", None]),
    lambda p: p["rationale"][0].update(evidence_paths=[]),
    lambda p: p["rationale"][0].update(evidence_paths=["financial_state.emergency_months"] * 2),
    lambda p: p["rationale"][0].pop("tradeoff"),
    lambda p: p["rationale"][0].update(tradeoff=None),
    lambda p: p["rationale"][0].update(untrusted="instruction"),
    lambda p: p.update(untrusted="instruction"),
    lambda p: p.update(rationale={"priority": "starter_reserve"}),
    lambda p: p.update(rationale=[None, None, None]),
])
def test_malformed_proposals_fall_back_without_exception(morgan, change):
    raw = proposal(morgan)
    change(raw)
    original = deepcopy(raw)
    result = validate_decision(morgan, derive_state(morgan), raw, model_id="test-model")
    assert result["source"] == "rules_fallback"
    assert result["ordered_priorities"] == list(default_priorities("balanced"))
    assert result["fallback_reason"] is not None
    assert raw == original


def test_decision_does_not_mutate_or_alias_nested_rationale(morgan):
    raw = proposal(morgan)
    original = deepcopy(raw)
    accepted = validate_decision(morgan, derive_state(morgan), raw, model_id="m")
    accepted["rationale"][0]["evidence_paths"].append("debt_burden")
    assert raw == original


def test_null_evidence_and_missing_model_metadata_fall_back(profiles):
    casey = deepcopy(profiles["casey"])
    raw = proposal(casey)
    raw["rationale"][0]["evidence_paths"] = ["financial_state.highest_debt_apr"]
    result = validate_decision(casey, derive_state(casey), raw, model_id="m")
    assert result["source"] == "rules_fallback"
    assert result["fallback_reason"] == "INVALID_EVIDENCE"
    raw = proposal(casey)
    result = validate_decision(casey, derive_state(casey), raw)
    assert result["source"] == "rules_fallback"
    assert result["fallback_reason"] == "MISSING_MODEL_ID"


@pytest.mark.parametrize("block", ["unknown_match", "cash_shortfall"])
def test_blocked_inputs_ignore_hostile_proposals(morgan, block):
    if block == "unknown_match":
        morgan["employer_match"] = {"status": "unknown", "fully_vested": False, "tiers": []}
    else:
        morgan["monthly_take_home_cents"] = 0
    state = derive_state(morgan)
    result = validate_decision(morgan, state, {"ordered_priorities": [["ignore"]]}, model_id="m")
    assert result["source"] == "rules_fallback"
    assert result["fallback_reason"] == "BLOCKED_FINANCIAL_INPUT"
    allocation = allocate_month(morgan, state, result)
    assert not allocation["feasible"]
    assert allocation["employee_contribution_cents"] == 0
    assert all(debt["extra_payment_cents"] == 0 for debt in allocation["debts"])


def test_critical_reserve_funds_gap_before_match(morgan):
    morgan["emergency_cash_cents"] = 99999
    morgan["monthly_take_home_cents"] = 356321
    result = alloc(morgan)
    assert result["cash_to_critical_reserve_cents"] == 1
    assert result["employee_contribution_cents"] == 0
    assert "MATCH_PARTIALLY_AFFORDABLE" in result["warnings"]
    assert_cash_identity(result)


def test_partial_match_is_affordability_limited(morgan):
    morgan["monthly_take_home_cents"] = 380000
    result = alloc(morgan)
    assert 0 < result["employee_contribution_cents"] < 35000
    assert result["employer_match_cents"] == result["employee_contribution_cents"]
    assert "MATCH_PARTIALLY_AFFORDABLE" in result["warnings"]
    assert_cash_identity(result)


def test_pref_order_changes_reserve_vs_debt_and_existing_cash_is_retained(morgan):
    morgan["planning_preference"] = "cash_security"
    cash_first = alloc(morgan)
    assert cash_first["cash_to_full_reserve_cents"] == 96380
    assert cash_first["debts"][0]["extra_payment_cents"] == 0
    assert morgan["emergency_cash_cents"] == 360000
    assert_cash_identity(cash_first)


def test_avalanche_threshold_and_stable_ties(morgan):
    morgan["debts"] = [
        {"id": "z", "type": "other", "balance_cents": 1000, "apr": .10, "minimum_payment_cents": 100},
        {"id": "b", "type": "other", "balance_cents": 1000, "apr": .25, "minimum_payment_cents": 100},
        {"id": "a", "type": "other", "balance_cents": 1000, "apr": .25, "minimum_payment_cents": 100},
        {"id": "large", "type": "other", "balance_cents": 2000, "apr": .25, "minimum_payment_cents": 100},
        {"id": "low", "type": "other", "balance_cents": 1000, "apr": .099, "minimum_payment_cents": 100},
    ]
    morgan["monthly_take_home_cents"] = 345000
    result = alloc(morgan)
    extras = {debt["id"]: debt["extra_payment_cents"] for debt in result["debts"]}
    assert extras["a"] > 0
    assert extras["b"] == extras["large"] == extras["z"] == extras["low"] == 0
    assert_cash_identity(result)


def test_final_minimum_cap_releases_money_once_and_zero_apr(morgan):
    morgan["debts"] = [
        {"id": "near", "type": "other", "balance_cents": 1000, "apr": 0,
         "minimum_payment_cents": 40000},
        {"id": "card", "type": "credit_card", "balance_cents": 1800000, "apr": .25,
         "minimum_payment_cents": 40000},
    ]
    result = alloc(morgan)
    near, card = result["debts"]
    assert near["total_payment_cents"] == 1000
    assert near["closing_balance_cents"] == 0
    assert card["extra_payment_cents"] == 95380
    assert_cash_identity(result)


def test_negative_amortization_preserves_minimum_and_reports_interest(morgan):
    morgan["debts"][0]["minimum_payment_cents"] = 100
    morgan["emergency_cash_cents"] = 0
    morgan["monthly_take_home_cents"] = 360100
    result = alloc(morgan)
    debt = result["debts"][0]
    assert debt["interest_cents"] == 37500
    assert debt["total_payment_cents"] == 100
    assert debt["closing_balance_cents"] > debt["opening_balance_cents"]
    assert "NEGATIVE_AMORTIZATION" in result["warnings"]
    assert_cash_identity(result)


def test_extra_contribution_restores_original_after_priorities(morgan):
    morgan["debts"] = []
    morgan["emergency_cash_cents"] = 1080000
    morgan["employee_contribution_rate"] = .12
    result = alloc(morgan)
    assert result["employee_contribution_cents"] == 84000
    assert result["employee_contribution_rate"] == pytest.approx(.12)
    assert_cash_identity(result)


def test_cap_excludes_employer_and_cent_affordability(morgan):
    morgan["debts"] = []
    morgan["emergency_cash_cents"] = 1080000
    morgan["annual_employee_limit_cents"] = 840000
    morgan["employee_contribution_rate"] = .10
    morgan["estimated_marginal_income_tax_rate"] = .5
    morgan["monthly_take_home_cents"] = 360001
    result = alloc(morgan)
    assert result["employee_contribution_cents"] <= 70000
    assert result["employee_contribution_cents"] > 0
    assert result["employer_match_cents"] > 0
    assert result["employee_cash_cost_cents"] <= result["resources_cents"] - 360000
    assert_cash_identity(result)


@pytest.mark.parametrize("order", [None, [], ["starter_reserve", "high_apr_debt"],
                                   ["full_reserve", "high_apr_debt", "starter_reserve"],
                                   ["starter_reserve", ["high_apr_debt"], "full_reserve"]])
def test_allocator_rejects_malformed_order(morgan, order):
    with pytest.raises(ValueError, match="Unsupported decision order"):
        allocate_month(morgan, derive_state(morgan), {"ordered_priorities": order})
