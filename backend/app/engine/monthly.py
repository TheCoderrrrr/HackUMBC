"""The numerical handoff between policy (Developer B) and simulation (C).

These frozen values deliberately contain amounts, not display text. B can
import this module without importing the simulator. A's public schemas may
validate the resulting projection/evaluation dictionaries at the API edge.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal


Strategy = Literal["current", "adaptive", "custom"]


class EngineInvariantError(RuntimeError):
    """An allocator or simulation result violated a financial identity."""


class MissingHandoffError(RuntimeError):
    """A required Developer A/B integration function is not installed."""


class InfeasibleScenario(ValueError):
    """An explicit Custom scenario cannot be funded at a projected month."""

    def __init__(self, month: int, shortfall_cents: int, reason: str = "cash",
                 rate: float | None = None) -> None:
        self.month = month
        self.shortfall_cents = shortfall_cents
        # "cash": the budget can't cover essentials plus the election.
        # "cap": the election exceeds the annual contribution limit (the shortfall is the
        # excess over the cap, not a budget gap). REPORT A8.
        self.reason = reason
        # The fixed employee rate that was rejected, when one was requested.
        self.rate = rate
        super().__init__(
            f"Custom scenario is short {shortfall_cents} cents in month {month} ({reason})"
        )


@dataclass(frozen=True)
class DebtMonth:
    id: str
    opening_balance_cents: int
    apr: float
    interest_cents: int
    amount_due_cents: int
    minimum_payment_cents: int


@dataclass(frozen=True)
class MonthlyInputs:
    month: int
    months_until_retirement: int
    annual_gross_salary_cents: int
    annual_employee_limit_cents: int
    gross_monthly_salary_cents: int
    resources_before_retirement_cents: int
    living_expenses_cents: int
    employee_limit_cents: int
    opening_cash_cents: int
    opening_retirement_balance_cents: int
    debts: tuple[DebtMonth, ...]


@dataclass(frozen=True)
class DebtPayment:
    id: str
    minimum_cents: int
    extra_cents: int

    @property
    def total_cents(self) -> int:
        return self.minimum_cents + self.extra_cents


@dataclass(frozen=True)
class MonthlyAllocation:
    feasible: bool
    block_code: str | None = None
    employee_contribution_cents: int = 0
    employee_contribution_rate: float | None = None
    employee_cash_cost_cents: int = 0
    employer_match_cents: int = 0
    debt_payments: tuple[DebtPayment, ...] = ()
    debt_months: tuple[DebtMonth, ...] = ()
    cash_added_cents: int = 0
    shortfall_cents: int = 0
    warnings: tuple[str, ...] = ()
    facts: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class ProjectionPoint:
    month: int
    retirement_balance_cents: int
    cash_cents: int
    debt_cents: int


@dataclass(frozen=True)
class Projection:
    strategy: Strategy
    retirement_age: int
    feasible: bool
    shortfall_cents: int | None
    retirement_balance_nominal_cents: int | None
    retirement_balance_today_cents: int | None
    cash_nominal_cents: int | None
    debt_nominal_cents: int | None
    cumulative_debt_interest_cents: int | None
    debt_free_month: int | None
    starter_reserve_month: int | None
    full_reserve_month: int | None
    points: tuple[ProjectionPoint, ...]


@dataclass(frozen=True)
class SimulationRun:
    projection: Projection
    opening_allocation: MonthlyAllocation | None
    warnings: tuple[str, ...]
