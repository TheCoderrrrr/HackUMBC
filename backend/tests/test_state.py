"""Financial foundation contract: exact cents, missing data, and safe inputs."""

import json
import math
from copy import deepcopy

import pytest

from app.engine.money import (
    capped_minimum_payment_cents,
    contribution_cash_cost_for_rate_cents,
    employee_contribution_cents,
    equity_weight,
    monthly_gross_cents,
)
from app.engine.state import derive_state, recommendation_context
from app.engine.validation import ProfileValidationError, validate_profile


def _leaves(value, prefix=""):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from _leaves(child, f"{prefix}.{key}" if prefix else key)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _leaves(child, f"{prefix}.{index}")
    else:
        yield prefix


def test_fixture_provenance_covers_every_input(profiles):
    assert set(profiles) == {"jordan", "morgan", "casey"}
    for profile in profiles.values():
        validate_profile(profile)
        paths = set(_leaves({key: value for key, value in profile.items() if key != "provenance"}))
        assert set(profile["provenance"]) == paths
        assert all(item == {"source": "fixture", "as_of_date": "2026-09-26"}
                   for item in profile["provenance"].values())


@pytest.mark.parametrize("name,expected", [
    ("morgan", {"months_until_retirement": 384, "gross_monthly_salary_cents": 700000,
                "current_employee_contribution_cents": 56000,
                "current_employee_cash_cost_cents": 43680,
                "monthly_resources_before_retirement_cents": 523680,
                "monthly_required_debt_payments_cents": 40000,
                "monthly_allocatable_budget_cents": 123680,
                "current_monthly_surplus_cents": 80000,
                "emergency_months": 1.0, "critical_reserve_target_cents": 100000,
                "starter_reserve_target_cents": 360000, "full_reserve_target_cents": 1080000,
                "employee_rate_for_full_match": .05,
                "current_monthly_employer_match_cents": 35000,
                "maximum_monthly_employer_match_cents": 35000,
                "match_capture_fraction": 1.0, "high_interest_debt_cents": 1800000,
                "highest_debt_apr": .25, "baseline_equity_weight": .90,
                "warnings": ["SIMPLIFIED_TAX_ESTIMATE"]}),
    ("casey", {"months_until_retirement": 84, "gross_monthly_salary_cents": 916667,
               "current_employee_contribution_cents": 110000,
               "current_employee_cash_cost_cents": 85800,
               "monthly_resources_before_retirement_cents": 675800,
               "monthly_required_debt_payments_cents": 0,
               "monthly_allocatable_budget_cents": 225800,
               "current_monthly_surplus_cents": 140000,
               "emergency_months": 8.0, "critical_reserve_target_cents": 100000,
               "starter_reserve_target_cents": 450000, "full_reserve_target_cents": 1350000,
               "employee_rate_for_full_match": .05,
               "current_monthly_employer_match_cents": 45833,
               "maximum_monthly_employer_match_cents": 45833,
               "match_capture_fraction": 1.0, "high_interest_debt_cents": 0,
               "highest_debt_apr": None, "baseline_equity_weight": .605,
               "warnings": ["SIMPLIFIED_TAX_ESTIMATE"]}),
])
def test_exact_fixture_state(profiles, name, expected):
    original = deepcopy(profiles[name])
    actual = derive_state(profiles[name])
    assert actual == expected
    assert profiles[name] == original
    assert json.loads(json.dumps(actual, allow_nan=False)) == actual


def test_tiered_full_and_partial_matching(morgan):
    morgan["employer_match"]["tiers"] = [
        {"employee_rate_from": 0, "employee_rate_to": .03, "match_per_employee_dollar": 1},
        {"employee_rate_from": .03, "employee_rate_to": .05, "match_per_employee_dollar": .5},
    ]
    morgan["employee_contribution_rate"] = .04
    partial = derive_state(morgan)
    assert partial["employee_rate_for_full_match"] == .05
    assert partial["current_monthly_employer_match_cents"] == 24500
    assert partial["maximum_monthly_employer_match_cents"] == 28000
    assert partial["match_capture_fraction"] == .875
    morgan["employee_contribution_rate"] = .05
    assert derive_state(morgan)["current_monthly_employer_match_cents"] == 28000


@pytest.mark.parametrize("vested", [False, True])
def test_none_matching_has_zero_value_and_null_capture(morgan, vested):
    morgan["employer_match"] = {"status": "none", "fully_vested": vested, "tiers": []}
    absent = derive_state(morgan)
    assert absent["employee_rate_for_full_match"] == 0
    assert absent["current_monthly_employer_match_cents"] == 0
    assert absent["maximum_monthly_employer_match_cents"] == 0
    assert absent["match_capture_fraction"] is None


@pytest.mark.parametrize("status,vested", [("unknown", False), ("unknown", True), ("confirmed", False)])
def test_uncertain_matching_is_not_zero(morgan, status, vested):
    morgan["employer_match"]["status"] = status
    morgan["employer_match"]["fully_vested"] = vested
    if status == "unknown":
        morgan["employer_match"]["tiers"] = []
    state = derive_state(morgan)
    assert state["employee_rate_for_full_match"] is None
    assert state["current_monthly_employer_match_cents"] is None
    assert state["maximum_monthly_employer_match_cents"] is None
    assert state["match_capture_fraction"] is None
    assert "MISSING_REQUIRED_INPUT" in state["warnings"]


def test_debt_minimum_caps_and_high_apr_inclusive(morgan):
    morgan["debts"] = [
        {"id": "near", "type": "other", "balance_cents": 10000, "apr": 0,
         "minimum_payment_cents": 40000},
        {"id": "threshold", "type": "credit_card", "balance_cents": 50000,
         "apr": .10, "minimum_payment_cents": 1000},
        {"id": "below", "type": "student_loan", "balance_cents": 20000,
         "apr": .099, "minimum_payment_cents": 500},
    ]
    state = derive_state(morgan)
    assert capped_minimum_payment_cents(morgan["debts"][0]) == 10000
    assert state["monthly_required_debt_payments_cents"] == 11500
    assert state["high_interest_debt_cents"] == 50000
    assert state["highest_debt_apr"] == .10
    assert state["baseline_equity_weight"] == .90
    morgan["debts"][0]["balance_cents"] = 0
    assert capped_minimum_payment_cents(morgan["debts"][0]) == 0


def test_original_election_cap_is_rejected_without_mutation(morgan):
    morgan["annual_employee_limit_cents"] = 500000
    original = deepcopy(morgan)
    with pytest.raises(ProfileValidationError, match="employee_contribution_rate"):
        derive_state(morgan)
    assert morgan == original
    morgan["employee_contribution_rate"] = 0
    morgan["annual_employee_limit_cents"] = 0
    assert derive_state(morgan)["current_employee_contribution_cents"] == 0


def test_tax_treatment_and_fractional_monthly_salary(morgan):
    gross = monthly_gross_cents(101)
    assert employee_contribution_cents(gross, .5) == 4
    assert contribution_cash_cost_for_rate_cents(gross, .5, "roth", .22) == 4
    assert contribution_cash_cost_for_rate_cents(gross, .5, "traditional", .22) == 3
    morgan["contribution_tax_treatment"] = "roth"
    roth = derive_state(morgan)
    assert roth["current_employee_cash_cost_cents"] == 56000
    assert "SIMPLIFIED_TAX_ESTIMATE" not in roth["warnings"]


@pytest.mark.parametrize("months,weight", [(-1, .5), (0, .5), (60, .575),
                                           (84, .605), (120, .65), (180, .725),
                                           (240, .8), (300, .85), (360, .9), (480, .9)])
def test_glide_path(months, weight):
    assert equity_weight(months) == pytest.approx(weight)


def test_agent_context_is_normalized_and_identifiers_are_absent(morgan):
    state = derive_state(morgan)
    context = recommendation_context(morgan, state)
    assert context["debt_burden"] == pytest.approx(40000 * 12 / 8400000)
    assert context["savings_capacity"] == pytest.approx(80000 / 480000)
    assert context["financial_state"]["emergency_months"] == 1
    encoded = json.dumps(context, allow_nan=False)
    assert all(text not in encoded for text in ("Morgan", "morgan-card", "morgan", "bank", "provenance"))
    morgan["monthly_take_home_cents"] = 0
    zero = recommendation_context(morgan, derive_state(morgan))
    assert zero["savings_capacity"] is None
    assert math.isfinite(zero["debt_burden"])


@pytest.mark.parametrize("path,value", [
    ("age", None), ("age", True), ("age", 17), ("age", 76),
    ("retirement_age", 35), ("retirement_age", 81),
    ("annual_gross_salary_cents", 0), ("monthly_living_expenses_cents", 0),
    ("monthly_take_home_cents", -1), ("emergency_cash_cents", None),
    ("employee_contribution_rate", True), ("employee_contribution_rate", float("nan")),
    ("employee_contribution_rate", float("inf")), ("employee_contribution_rate", -0.01),
    ("estimated_marginal_income_tax_rate", .51), ("currency", "EUR"),
    ("as_of_date", "2026-02-30"), ("as_of_date", "09/26/2026"),
    ("contribution_tax_treatment", "pre-tax"),
])
def test_rejects_malformed_top_level(morgan, path, value):
    morgan[path] = value
    with pytest.raises(ProfileValidationError) as error:
        validate_profile(morgan)
    assert error.value.path == path


@pytest.mark.parametrize("mutation,path", [
    (lambda p: p["employer_match"].update(status="unknown"), "employer_match.tiers"),
    (lambda p: p["employer_match"].update(fully_vested=None), "employer_match.fully_vested"),
    (lambda p: p["employer_match"]["tiers"][0].update(employee_rate_from=.01), "employer_match.tiers.0"),
    (lambda p: p["employer_match"]["tiers"][0].update(employee_rate_to=0), "employer_match.tiers.0"),
    (lambda p: p["employer_match"]["tiers"][0].update(match_per_employee_dollar=2.1),
     "employer_match.tiers.0.match_per_employee_dollar"),
    (lambda p: p["debts"].append(deepcopy(p["debts"][0])), "debts.1.id"),
    (lambda p: p["debts"][0].update(minimum_payment_cents=0), "debts.0.minimum_payment_cents"),
    (lambda p: p["debts"][0].update(apr=float("inf")), "debts.0.apr"),
    (lambda p: p["debts"][0].update(apr=1.01), "debts.0.apr"),
    (lambda p: p["debts"][0].update(balance_cents=True), "debts.0.balance_cents"),
])
def test_rejects_malformed_nested_input(morgan, mutation, path):
    mutation(morgan)
    with pytest.raises(ProfileValidationError) as error:
        validate_profile(morgan)
    assert error.value.path == path
