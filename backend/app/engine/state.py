"""Derived financial indicators for deterministic policy and bounded AI context."""

from __future__ import annotations

from typing import Mapping

from .assumptions import MODEL_ASSUMPTIONS
from .money import (
    capped_minimum_payment_cents, cents, contribution_cash_cost_for_rate_cents, decimal,
    employee_contribution_cents, employer_match_cents, equity_weight,
    full_match_employee_rate, monthly_gross_cents,
)
from .validation import validate_profile


def derive_state(profile: Mapping[str, object]) -> dict[str, object]:
    """Return the documented FinancialState using current, unmodified inputs."""
    validate_profile(profile)
    gross = monthly_gross_cents(profile["annual_gross_salary_cents"])
    employee = employee_contribution_cents(gross, profile["employee_contribution_rate"])
    cost = contribution_cash_cost_for_rate_cents(
        gross, profile["employee_contribution_rate"], profile["contribution_tax_treatment"],
        profile["estimated_marginal_income_tax_rate"],
    )
    resources = profile["monthly_take_home_cents"] + cost
    required = sum(capped_minimum_payment_cents(debt) for debt in profile["debts"])
    living = profile["monthly_living_expenses_cents"]
    budget = resources - living - required
    match = profile["employer_match"]
    full_rate = full_match_employee_rate(match)
    current_match = employer_match_cents(gross, profile["employee_contribution_rate"], match)
    maximum_match = None if full_rate is None else employer_match_cents(gross, full_rate, match)
    if match["status"] == "none":
        maximum_match = 0
    capture = (
        None if maximum_match is None or maximum_match == 0
        else current_match / maximum_match
    )
    positive_debts = [debt for debt in profile["debts"] if debt["balance_cents"] > 0]
    high_threshold = decimal(MODEL_ASSUMPTIONS["high_interest_apr_threshold"])
    warnings = []
    if profile["contribution_tax_treatment"] == "traditional":
        warnings.append("SIMPLIFIED_TAX_ESTIMATE")
    if match["status"] == "unknown" or (match["status"] == "confirmed" and not match["fully_vested"]):
        warnings.append("MISSING_REQUIRED_INPUT")
    if budget < 0:
        warnings.append("CASH_FLOW_SHORTFALL")
    return {
        "months_until_retirement": 12 * (profile["retirement_age"] - profile["age"]),
        "gross_monthly_salary_cents": cents(gross),
        "current_employee_contribution_cents": employee,
        "current_employee_cash_cost_cents": cost,
        "monthly_resources_before_retirement_cents": resources,
        "monthly_required_debt_payments_cents": required,
        "monthly_allocatable_budget_cents": budget,
        "current_monthly_surplus_cents": budget - cost,
        "emergency_months": float(decimal(profile["emergency_cash_cents"]) / decimal(living)),
        "critical_reserve_target_cents": min(MODEL_ASSUMPTIONS["critical_reserve_cap_cents"], living),
        "starter_reserve_target_cents": living * MODEL_ASSUMPTIONS["starter_reserve_months"],
        "full_reserve_target_cents": living * MODEL_ASSUMPTIONS["full_reserve_months"],
        "employee_rate_for_full_match": None if full_rate is None else float(full_rate),
        "current_monthly_employer_match_cents": current_match,
        "maximum_monthly_employer_match_cents": maximum_match,
        "match_capture_fraction": capture,
        "high_interest_debt_cents": sum(debt["balance_cents"] for debt in positive_debts if decimal(debt["apr"]) >= high_threshold),
        "highest_debt_apr": None if not positive_debts else float(max(decimal(debt["apr"]) for debt in positive_debts)),
        "baseline_equity_weight": equity_weight(12 * (profile["retirement_age"] - profile["age"])),
        "warnings": warnings,
    }


def recommendation_context(profile: Mapping[str, object], state: Mapping[str, object]) -> dict[str, object]:
    """Only normalized, allowlisted indicators for the Recommendation Agent."""
    validate_profile(profile)
    take_home = profile["monthly_take_home_cents"]
    context = {
        "planning_preference": profile.get("planning_preference", "balanced"),
        "emergency_cash_cents": profile["emergency_cash_cents"],
        "debt_burden": float(decimal(state["monthly_required_debt_payments_cents"]) * 12 / decimal(profile["annual_gross_salary_cents"])),
        "savings_capacity": None if take_home == 0 else float(decimal(state["current_monthly_surplus_cents"]) / decimal(take_home)),
    }
    context["financial_state"] = {
        key: state[key] for key in (
            "months_until_retirement", "emergency_months", "critical_reserve_target_cents",
            "starter_reserve_target_cents", "full_reserve_target_cents",
            "monthly_allocatable_budget_cents", "current_monthly_surplus_cents",
            "monthly_required_debt_payments_cents", "high_interest_debt_cents",
            "highest_debt_apr", "employee_rate_for_full_match", "match_capture_fraction",
        )
    }
    return context
