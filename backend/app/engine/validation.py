"""Canonical engine input validation, independent of the API schema layer."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
import re
from typing import Mapping

from .money import decimal


class ProfileValidationError(ValueError):
    def __init__(self, path: str, message: str):
        self.path = path
        super().__init__(f"{path}: {message}")


def _fail(path: str, message: str) -> None:
    raise ProfileValidationError(path, message)


def _mapping(value: object, path: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        _fail(path, "must be an object")
    return value


def _text(value: object, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail(path, "must be a nonempty string")
    return value


def _integer(value: object, path: str, minimum: int = 0, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        _fail(path, "must be an integer")
    if value < minimum or (maximum is not None and value > maximum):
        _fail(path, "is outside the supported range")
    return value


def _rate(value: object, path: str, maximum: str = "1") -> Decimal:
    if isinstance(value, (bool, str)) or value is None:
        _fail(path, "must be a finite number")
    try:
        result = decimal(value)
    except ValueError:
        _fail(path, "must be a finite number")
    if not Decimal(0) <= result <= Decimal(maximum):
        _fail(path, "is outside the supported range")
    return result


def _date(value: object, path: str) -> None:
    text = _text(value, path)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        _fail(path, "must be an ISO date")
    try:
        date.fromisoformat(text)
    except ValueError:
        _fail(path, "must be an ISO date")


def validate_profile(profile: Mapping[str, object]) -> None:
    """Reject unsupported canonical values; unknown matching remains a valid blocked input."""
    p = _mapping(profile, "profile")
    if p.get("schema_version") != "1":
        _fail("schema_version", "must be 1")
    _text(p.get("id"), "id")
    _text(p.get("name"), "name")
    _date(p.get("as_of_date"), "as_of_date")
    if p.get("currency") != "USD":
        _fail("currency", "only USD is supported")
    if p.get("source") not in {"demo", "plaid_sandbox", "manual"}:
        _fail("source", "unsupported source")
    age = _integer(p.get("age"), "age", 18, 75)
    retirement_age = _integer(p.get("retirement_age"), "retirement_age", 19, 80)
    if retirement_age <= age:
        _fail("retirement_age", "must be greater than age")
    salary = _integer(p.get("annual_gross_salary_cents"), "annual_gross_salary_cents", 1)
    _integer(p.get("monthly_take_home_cents"), "monthly_take_home_cents")
    _integer(p.get("monthly_living_expenses_cents"), "monthly_living_expenses_cents", 1)
    rate = _rate(p.get("employee_contribution_rate"), "employee_contribution_rate")
    if p.get("contribution_tax_treatment") not in {"traditional", "roth"}:
        _fail("contribution_tax_treatment", "unsupported treatment")
    _rate(p.get("estimated_marginal_income_tax_rate"), "estimated_marginal_income_tax_rate", "0.5")
    cap = _integer(p.get("annual_employee_limit_cents"), "annual_employee_limit_cents")
    if Decimal(salary) * rate > cap:
        _fail("employee_contribution_rate", "original annualized election exceeds employee cap")
    _integer(p.get("retirement_balance_cents"), "retirement_balance_cents")
    _integer(p.get("emergency_cash_cents"), "emergency_cash_cents")
    if p.get("planning_preference", "balanced") not in {"balanced", "cash_security", "debt_reduction"}:
        _fail("planning_preference", "unsupported preference")

    match = _mapping(p.get("employer_match"), "employer_match")
    status = match.get("status")
    if status not in {"confirmed", "none", "unknown"}:
        _fail("employer_match.status", "unsupported status")
    if not isinstance(match.get("fully_vested"), bool):
        _fail("employer_match.fully_vested", "must be boolean")
    tiers = match.get("tiers")
    if not isinstance(tiers, list):
        _fail("employer_match.tiers", "must be an array")
    if status != "confirmed" and tiers:
        _fail("employer_match.tiers", "must be empty unless matching is confirmed")
    if status == "confirmed" and not 1 <= len(tiers) <= 8:
        _fail("employer_match.tiers", "confirmed match requires one to eight tiers")
    previous_end = Decimal(0)
    for i, raw_tier in enumerate(tiers):
        tier = _mapping(raw_tier, f"employer_match.tiers.{i}")
        start = _rate(tier.get("employee_rate_from"), f"employer_match.tiers.{i}.employee_rate_from")
        end = _rate(tier.get("employee_rate_to"), f"employer_match.tiers.{i}.employee_rate_to")
        multiplier = _rate(tier.get("match_per_employee_dollar"), f"employer_match.tiers.{i}.match_per_employee_dollar", "2")
        if start != previous_end or end <= start or multiplier <= 0:
            _fail(f"employer_match.tiers.{i}", "tiers must be contiguous, increasing, and positive")
        previous_end = end

    debts = p.get("debts")
    if not isinstance(debts, list) or len(debts) > 20:
        _fail("debts", "must be an array with at most 20 debts")
    seen: set[str] = set()
    for i, raw_debt in enumerate(debts):
        debt = _mapping(raw_debt, f"debts.{i}")
        debt_id = _text(debt.get("id"), f"debts.{i}.id")
        if debt_id in seen:
            _fail(f"debts.{i}.id", "duplicate debt ID")
        seen.add(debt_id)
        if debt.get("type") not in {"credit_card", "student_loan", "other"}:
            _fail(f"debts.{i}.type", "unsupported debt type")
        balance = _integer(debt.get("balance_cents"), f"debts.{i}.balance_cents")
        _rate(debt.get("apr"), f"debts.{i}.apr")
        minimum = _integer(debt.get("minimum_payment_cents"), f"debts.{i}.minimum_payment_cents")
        if balance > 0 and minimum == 0:
            _fail(f"debts.{i}.minimum_payment_cents", "positive balance requires a confirmed minimum")

    provenance = _mapping(p.get("provenance"), "provenance")
    for path, entry in provenance.items():
        item = _mapping(entry, f"provenance.{path}")
        if item.get("source") not in {"fixture", "plaid_sandbox", "user_confirmed"}:
            _fail(f"provenance.{path}.source", "unsupported source")
        _date(item.get("as_of_date"), f"provenance.{path}.as_of_date")
