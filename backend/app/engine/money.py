"""Exact cent accounting helpers shared by state, policy, and simulation."""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Mapping

CENT = Decimal("1")
TWELVE = Decimal(12)


def decimal(value: int | float | str | Decimal) -> Decimal:
    """Convert external numeric values without binary-float arithmetic."""
    if isinstance(value, bool) or value is None:
        raise ValueError("Expected a finite numeric value")
    try:
        result = Decimal(str(value))
    except Exception as exc:
        raise ValueError("Expected a finite numeric value") from exc
    if not result.is_finite():
        raise ValueError("Expected a finite numeric value")
    return result


def cents(value: Decimal | int | float | str) -> int:
    return int(decimal(value).quantize(CENT, rounding=ROUND_HALF_UP))


def monthly_gross_cents(annual_salary_cents: int) -> Decimal:
    """Keep annual salary / 12 unrounded until a monetary result is needed."""
    return decimal(annual_salary_cents) / TWELVE


def employee_contribution_cents(gross_monthly_cents: Decimal, rate: float | Decimal) -> int:
    return cents(gross_monthly_cents * decimal(rate))


def contribution_cash_cost_cents(
    contribution_cents: int,
    tax_treatment: str,
    marginal_tax_rate: float | Decimal,
) -> int:
    factor = Decimal(1) if tax_treatment == "roth" else Decimal(1) - decimal(marginal_tax_rate)
    if tax_treatment not in {"roth", "traditional"}:
        raise ValueError("Unsupported contribution tax treatment")
    return cents(decimal(contribution_cents) * factor)


def contribution_cash_cost_for_rate_cents(
    gross_monthly_cents: Decimal,
    rate: float | Decimal,
    tax_treatment: str,
    marginal_tax_rate: float | Decimal,
) -> int:
    """Round once after applying the rate and estimated tax factor."""
    if tax_treatment not in {"roth", "traditional"}:
        raise ValueError("Unsupported contribution tax treatment")
    factor = Decimal(1) if tax_treatment == "roth" else Decimal(1) - decimal(marginal_tax_rate)
    return cents(gross_monthly_cents * decimal(rate) * factor)


def monthly_debt_interest_cents(balance_cents: int, apr: float | Decimal) -> int:
    return cents(decimal(balance_cents) * decimal(apr) / TWELVE)


def capped_minimum_payment_cents(debt: Mapping[str, object]) -> int:
    balance = int(debt["balance_cents"])
    if balance == 0:
        return 0
    due = balance + monthly_debt_interest_cents(balance, debt["apr"])
    return min(int(debt["minimum_payment_cents"]), due)


def match_rate(employee_rate: float | Decimal, match: Mapping[str, object]) -> Decimal | None:
    """Return employer rate, or None if matching is unconfirmed/unvested."""
    if match["status"] == "none":
        return Decimal(0)
    if match["status"] != "confirmed" or not match["fully_vested"]:
        return None
    rate = decimal(employee_rate)
    total = Decimal(0)
    for tier in match["tiers"]:
        start = decimal(tier["employee_rate_from"])
        end = decimal(tier["employee_rate_to"])
        total += decimal(tier["match_per_employee_dollar"]) * max(Decimal(0), min(rate, end) - start)
    return total


def full_match_employee_rate(match: Mapping[str, object]) -> Decimal | None:
    if match["status"] == "none":
        return Decimal(0)
    if match["status"] != "confirmed" or not match["fully_vested"]:
        return None
    return decimal(match["tiers"][-1]["employee_rate_to"])


def employer_match_cents(
    gross_monthly_cents: Decimal, employee_rate: float | Decimal, match: Mapping[str, object]
) -> int | None:
    rate = match_rate(employee_rate, match)
    return None if rate is None else cents(gross_monthly_cents * rate)


def equity_weight(months_until_retirement: int) -> float:
    """Interpolate the documented glide path from remaining whole months."""
    remaining = max(0, months_until_retirement)
    anchors = ((0, Decimal("0.50")), (120, Decimal("0.65")),
               (240, Decimal("0.80")), (360, Decimal("0.90")))
    if remaining >= 360:
        return 0.90
    for (left_month, left_weight), (right_month, right_weight) in zip(anchors, anchors[1:]):
        if remaining <= right_month:
            return float(left_weight + (right_weight - left_weight)
                         * decimal(remaining - left_month) / decimal(right_month - left_month))
    raise AssertionError("Unreachable glide-path horizon")
