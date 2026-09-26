"""Reusable monthly snapshots and strategy accounting for simulations."""

from copy import deepcopy

import pytest

from app.engine.policy import MONTH_KEYS, allocate_month, default_priorities, validate_decision
from app.engine.state import derive_state


def inputs(profile):
    state = derive_state(profile)
    decision = validate_decision(profile, state, None)
    return state, decision


def snapshot(profile, state):
    month = {key: deepcopy(profile[key]) for key in MONTH_KEYS if key in profile}
    month["monthly_resources_before_retirement_cents"] = state["monthly_resources_before_retirement_cents"]
    return month


def cash_identity(result):
    if result["feasible"]:
        assert result["resources_cents"] == (
            result["living_expenses_cents"]
            + sum(debt["total_payment_cents"] for debt in result["debts"])
            + result["employee_cash_cost_cents"] + result["total_cash_added_cents"]
        )
        assert all(0 <= debt["total_payment_cents"] <= debt["amount_due_cents"]
                   and debt["closing_balance_cents"] >= 0 for debt in result["debts"])


def test_snapshot_uses_updated_independent_values_and_preserves_inputs(morgan):
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    month.update(annual_gross_salary_cents=9600000,
                 monthly_resources_before_retirement_cents=800000,
                 monthly_living_expenses_cents=400000,
                 annual_employee_limit_cents=1200000,
                 emergency_cash_cents=50000)
    month["debts"][0]["balance_cents"] = 100000
    originals = deepcopy((morgan, state, decision, month))
    result = allocate_month(morgan, state, decision, month=month)
    assert result["feasible"]
    assert result["resources_cents"] == 800000
    assert result["living_expenses_cents"] == 400000
    assert result["debts"][0]["opening_balance_cents"] == 100000
    assert result["cash_to_critical_reserve_cents"] == 50000
    assert result["employee_contribution_cents"] <= 100000
    assert (morgan, state, decision, month) == originals
    cash_identity(result)


def test_current_keeps_fixed_election_minimum_debt_and_cash_only(morgan):
    state, decision = inputs(morgan)
    result = allocate_month(morgan, state, decision, strategy="current")
    assert result["feasible"]
    assert result["employee_contribution_cents"] == 56000
    assert result["employee_contribution_rate"] == pytest.approx(.08)
    assert result["debts"][0]["total_payment_cents"] == 40000
    assert result["debts"][0]["extra_payment_cents"] == 0
    assert result["total_cash_added_cents"] == 80000
    assert result["cash_to_critical_reserve_cents"] == 0
    assert result["cash_to_starter_reserve_cents"] == 0
    assert result["cash_to_full_reserve_cents"] == 0
    cash_identity(result)


def test_custom_null_equals_adaptive_numerically(morgan):
    state, decision = inputs(morgan)
    adaptive = allocate_month(morgan, state, decision)
    custom = allocate_month(morgan, state, decision, strategy="custom")
    assert {key: value for key, value in adaptive.items() if key != "strategy"} == {
        key: value for key, value in custom.items() if key != "strategy"
    }


def test_custom_explicit_rate_is_fixed_before_critical_and_no_extra_retirement(morgan):
    morgan["emergency_cash_cents"] = 0
    state, decision = inputs(morgan)
    result = allocate_month(morgan, state, decision, strategy="custom", employee_contribution_rate=.05)
    assert result["feasible"]
    assert result["employee_contribution_cents"] == 35000
    assert result["employee_cash_cost_cents"] == 27300
    assert result["cash_to_critical_reserve_cents"] == 96380
    assert "CUSTOM_LIQUIDITY_DELAYED" in result["warnings"]
    cash_identity(result)


def test_fixed_rate_infeasible_retains_positive_gap_without_applied_payments(morgan):
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    month["monthly_resources_before_retirement_cents"] = 401000
    result = allocate_month(morgan, state, decision, month=month,
                            strategy="custom", employee_contribution_rate=.05)
    assert not result["feasible"]
    assert result["shortfall_cents"] == 26300
    assert "INFEASIBLE_SCENARIO" in result["warnings"]
    assert result["employee_contribution_cents"] == 0
    assert result["employee_cash_cost_cents"] == 0
    assert all(debt["total_payment_cents"] == 0 for debt in result["debts"])


def test_original_custom_cap_rejects_but_future_month_clips(morgan):
    state, decision = inputs(morgan)
    with pytest.raises(ValueError, match="original annual employee cap"):
        allocate_month(morgan, state, decision, strategy="custom", employee_contribution_rate=.5)
    month = snapshot(morgan, state)
    month["annual_employee_limit_cents"] = 120000
    for strategy, rate in (("current", None), ("custom", .05), ("adaptive", None)):
        result = allocate_month(morgan, state, decision, month=month,
                                strategy=strategy, employee_contribution_rate=rate)
        assert result["employee_contribution_cents"] <= 10000
        cash_identity(result)


def test_accepted_morgan_exception_survives_month_snapshot(morgan):
    morgan["planning_preference"] = "cash_security"
    state = derive_state(morgan)
    order = ["starter_reserve", "high_apr_debt", "full_reserve"]
    proposal = {"ordered_priorities": order, "rationale": [
        {"priority": priority, "summary": "Supported by the debt and cash facts",
         "evidence_paths": ["financial_state.high_interest_debt_cents"],
         "tradeoff": "Debt repayment delays cash growth."} for priority in order
    ]}
    decision = validate_decision(morgan, state, proposal, model_id="test-model",
                                 allow_morgan_exception=True)
    assert decision["source"] == "ai"
    month = snapshot(morgan, state)
    month["emergency_cash_cents"] = 400000
    month["debts"][0]["balance_cents"] = 1000000
    result = allocate_month(morgan, state, decision, month=month, allow_morgan_exception=True)
    assert result["debts"][0]["extra_payment_cents"] > 0
    assert decision["ordered_priorities"] == order
    cash_identity(result)


def test_final_payment_releases_cash_once_and_preserves_fixed_debt_terms(morgan):
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    month["debts"][0]["balance_cents"] = 1000
    first = allocate_month(morgan, state, decision, month=month)
    assert first["required_debt_payments_cents"] == first["debts"][0]["amount_due_cents"]
    assert first["debts"][0]["closing_balance_cents"] == 0
    assert first["debts"][0]["apr"] == .25
    assert first["debts"][0]["extra_payment_cents"] == 0
    cash_identity(first)
    second_month = deepcopy(month)
    second_month["debts"][0]["balance_cents"] = 0
    second = allocate_month(morgan, state, decision, month=second_month)
    assert second["required_debt_payments_cents"] == 0
    assert second["debts"][0]["total_payment_cents"] == 0
    assert second["total_cash_added_cents"] >= first["total_cash_added_cents"]
    cash_identity(second)


@pytest.mark.parametrize("change", [
    lambda m: m.pop("emergency_cash_cents"),
    lambda m: m.update(extra=1),
    lambda m: m.update(annual_gross_salary_cents=True),
    lambda m: m.update(monthly_resources_before_retirement_cents=None),
    lambda m: m.update(monthly_living_expenses_cents=-1),
    lambda m: m.update(annual_employee_limit_cents=float("inf")),
    lambda m: m.update(emergency_cash_cents=float("nan")),
    lambda m: m.update(debts=None),
    lambda m: m["debts"][0].update(balance_cents=True),
    lambda m: m["debts"][0].update(apr=float("nan")),
    lambda m: m["debts"][0].update(apr=None),
    lambda m: m["debts"][0].update(apr=.24),
    lambda m: m["debts"][0].update(minimum_payment_cents=39999),
    lambda m: m["debts"][0].update(type="other"),
    lambda m: m["debts"][0].update(id="new"),
    lambda m: m["debts"][0].update(extra=1),
])
def test_rejects_malformed_snapshots(morgan, change):
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    change(month)
    with pytest.raises(ValueError):
        allocate_month(morgan, state, decision, month=month)


@pytest.mark.parametrize("rate", [True, "0.05", float("nan"), float("inf"), -0.01, 1.01])
def test_rejects_malformed_custom_rate(morgan, rate):
    state, decision = inputs(morgan)
    with pytest.raises(ValueError):
        allocate_month(morgan, state, decision, strategy="custom", employee_contribution_rate=rate)


def test_tiny_salary_never_exceeds_one_hundred_percent_rate(morgan):
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    month.update(annual_gross_salary_cents=1, annual_employee_limit_cents=100000,
                 monthly_resources_before_retirement_cents=500000)
    result = allocate_month(morgan, state, decision, month=month)
    assert 0 <= result["employee_contribution_rate"] <= 1
    cash_identity(result)


def test_dynamic_shortfall_adds_warning(morgan):
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    month["monthly_resources_before_retirement_cents"] = 399999
    bad = allocate_month(morgan, state, decision, month=month)
    assert not bad["feasible"]
    assert bad["shortfall_cents"] == 1
    assert "CASH_FLOW_SHORTFALL" in bad["warnings"]


def test_resolved_original_shortfall_removes_warning(morgan):
    morgan["monthly_take_home_cents"] = 0
    old_state, old_decision = inputs(morgan)
    resolved = snapshot(morgan, old_state)
    resolved["monthly_resources_before_retirement_cents"] = 523680
    good = allocate_month(morgan, old_state, old_decision, month=resolved)
    assert good["feasible"]
    assert "CASH_FLOW_SHORTFALL" not in good["warnings"]
    cash_identity(good)


def test_dynamic_negative_amortization_warning(morgan):
    morgan["debts"][0]["minimum_payment_cents"] = 100
    state, decision = inputs(morgan)
    month = snapshot(morgan, state)
    month["monthly_resources_before_retirement_cents"] = 360100
    month["emergency_cash_cents"] = 0
    result = allocate_month(morgan, state, decision, month=month)
    assert result["feasible"]
    assert "NEGATIVE_AMORTIZATION" in result["warnings"]
    assert result["debts"][0]["closing_balance_cents"] > result["debts"][0]["opening_balance_cents"]
    cash_identity(result)


def test_two_month_strategy_cash_conservation_smoke(morgan):
    state, decision = inputs(morgan)
    for strategy, rate in (("adaptive", None), ("current", None), ("custom", .05)):
        first = allocate_month(morgan, state, decision,
                               strategy=strategy, employee_contribution_rate=rate)
        assert first["feasible"]
        cash_identity(first)
        month = snapshot(morgan, state)
        month["emergency_cash_cents"] += first["total_cash_added_cents"]
        month["debts"][0]["balance_cents"] = first["debts"][0]["closing_balance_cents"]
        month["annual_gross_salary_cents"] += 100
        month["monthly_resources_before_retirement_cents"] += 10
        second = allocate_month(morgan, state, decision, month=month,
                                strategy=strategy, employee_contribution_rate=rate)
        assert second["feasible"]
        cash_identity(second)
