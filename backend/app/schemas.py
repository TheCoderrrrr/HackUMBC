"""Shared API contract (BACKEND.md section 4).

Developer A owns these models. Money is integer USD cents; rates are fractions
(0.05 == 5%). Contract changes need updated contracts/examples and a Swift decode check.
"""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationInfo, field_validator, model_validator

SCHEMA_VERSION = "1"

# Ceiling of $100B keeps every derived and simulated amount far inside Swift's Int64.
MAX_CENTS = 10**13
Cents = Annotated[int, Field(le=MAX_CENTS, ge=-MAX_CENTS)]
Rate = float
Priority = Literal["starter_reserve", "high_apr_debt", "full_reserve"]
PlanningPreference = Literal["balanced", "cash_security", "debt_reduction"]
Scalar = str | int | float | bool | None


class Strict(BaseModel):
    """Unknown fields are rejected so typos never silently become defaults."""

    model_config = ConfigDict(extra="forbid")


# --- Profile -----------------------------------------------------------------


class MatchTier(Strict):
    employee_rate_from: Rate = Field(ge=0, le=1)
    employee_rate_to: Rate = Field(ge=0, le=1)
    match_per_employee_dollar: float = Field(gt=0, le=2.0)

    @model_validator(mode="after")
    def _ordered(self) -> MatchTier:
        if self.employee_rate_to <= self.employee_rate_from:
            raise ValueError("employee_rate_to must be greater than employee_rate_from")
        return self


class EmployerMatch(Strict):
    status: Literal["confirmed", "none", "unknown"]
    fully_vested: bool
    tiers: list[MatchTier] = Field(max_length=8)

    @model_validator(mode="after")
    def _tiers(self) -> EmployerMatch:
        if self.status != "confirmed":
            if self.tiers:
                raise ValueError("tiers must be empty when status is none or unknown")
            return self
        if not self.tiers:
            raise ValueError("confirmed matching needs at least one tier")
        if self.tiers[0].employee_rate_from != 0:
            raise ValueError("match tiers must start at 0")
        for prev, cur in zip(self.tiers, self.tiers[1:]):
            if cur.employee_rate_from != prev.employee_rate_to:
                raise ValueError("match tiers must be contiguous and non-overlapping")
        return self


class Debt(Strict):
    id: str = Field(min_length=1, max_length=64)
    type: Literal["credit_card", "student_loan", "other"]
    balance_cents: Cents = Field(ge=0)
    apr: Rate = Field(ge=0, le=1)
    minimum_payment_cents: Cents = Field(ge=0)

    @field_validator("minimum_payment_cents")
    @classmethod
    def _minimum(cls, value: int, info: ValidationInfo) -> int:
        if info.data.get("balance_cents", 0) > 0 and value <= 0:
            raise ValueError("Confirm the minimum payment for this debt.")
        return value


class Provenance(Strict):
    source: Literal["fixture", "plaid_sandbox", "user_confirmed"]
    as_of_date: date


class FinancialProfile(Strict):
    schema_version: Literal["1"] = SCHEMA_VERSION
    id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=100)
    as_of_date: date
    currency: Literal["USD"]
    source: Literal["demo", "plaid_sandbox", "manual"]  # manual: the user typed their own numbers
    age: int = Field(ge=18, le=75)
    retirement_age: int = Field(le=80)
    annual_gross_salary_cents: Cents = Field(gt=0)
    monthly_take_home_cents: Cents = Field(ge=0)
    monthly_living_expenses_cents: Cents = Field(gt=0)
    annual_employee_limit_cents: Cents = Field(ge=0)
    employee_contribution_rate: Rate = Field(ge=0, le=1)
    contribution_tax_treatment: Literal["traditional", "roth"]
    estimated_marginal_income_tax_rate: Rate = Field(ge=0, le=0.5)
    retirement_balance_cents: Cents = Field(ge=0)
    emergency_cash_cents: Cents = Field(ge=0)
    employer_match: EmployerMatch
    debts: list[Debt] = Field(max_length=20)
    planning_preference: PlanningPreference = "balanced"
    provenance: dict[str, Provenance]

    @field_validator("debts")
    @classmethod
    def _unique_debt_ids(cls, debts: list[Debt]) -> list[Debt]:
        ids = [d.id for d in debts]
        if len(ids) != len(set(ids)):
            raise ValueError("debt ids must be unique")
        return debts

    @field_validator("employee_contribution_rate")
    @classmethod
    def _election_within_cap(cls, value: float, info: ValidationInfo) -> float:
        salary, cap = info.data.get("annual_gross_salary_cents"), info.data.get("annual_employee_limit_cents")
        if salary is not None and cap is not None and Decimal(salary) * Decimal(str(value)) > cap:
            raise ValueError("The annual contribution election is above the employee contribution limit.")
        return value

    @field_validator("retirement_age")
    @classmethod
    def _retirement_after_age(cls, value: int, info: ValidationInfo) -> int:
        if "age" in info.data and value <= info.data["age"]:
            raise ValueError("retirement_age must be greater than age")
        return value


class Scenario(Strict):
    retirement_age: int = Field(le=80)
    employee_contribution_rate: Rate | None = Field(default=None, ge=0, le=1)


class EvaluateRequest(Strict):
    profile: FinancialProfile
    scenario: Scenario | None = None
    previous_decision_id: str | None = Field(default=None, max_length=128)
    # scenario.retirement_age > profile.age is checked in api.evaluate so the error
    # can point at "scenario.retirement_age".


# --- Derived state -------------------------------------------------------------


class FinancialState(Strict):
    months_until_retirement: int
    gross_monthly_salary_cents: Cents
    current_employee_contribution_cents: Cents
    current_employee_cash_cost_cents: Cents
    monthly_resources_before_retirement_cents: Cents
    monthly_required_debt_payments_cents: Cents
    monthly_allocatable_budget_cents: Cents
    current_monthly_surplus_cents: Cents
    emergency_months: float
    critical_reserve_target_cents: Cents
    starter_reserve_target_cents: Cents
    full_reserve_target_cents: Cents
    employee_rate_for_full_match: Rate | None
    current_monthly_employer_match_cents: Cents | None
    maximum_monthly_employer_match_cents: Cents | None
    match_capture_fraction: float | None
    high_interest_debt_cents: Cents
    highest_debt_apr: Rate | None
    baseline_equity_weight: float
    warnings: list[str]


# --- Plan ----------------------------------------------------------------------


class RecommendationAction(Strict):
    id: str
    rank: int
    category: Literal["cash_flow", "contribution", "emergency", "debt", "allocation"]
    status: Literal["action", "maintain", "blocked", "information"]
    monthly_cash_cost_cents: Cents
    employee_contribution_cents: Cents | None
    employee_contribution_rate: Rate | None
    debt_id: str | None
    target_balance_cents: Cents | None
    reason_codes: list[str]


class Reason(Strict):
    code: str
    template_key: str
    facts: dict[str, Scalar]
    input_paths: list[str]


class Plan(Strict):
    primary_action_id: str
    actions: list[RecommendationAction]
    reasons: list[Reason]


# --- Projections and assumptions ---------------------------------------------


class ProjectionPoint(Strict):
    month: int
    retirement_balance_cents: Cents
    cash_cents: Cents
    debt_cents: Cents


class Projection(Strict):
    strategy: Literal["current", "adaptive", "custom"]
    retirement_age: int
    feasible: bool
    shortfall_cents: Cents | None
    retirement_balance_nominal_cents: Cents | None
    retirement_balance_today_cents: Cents | None
    cash_nominal_cents: Cents | None
    debt_nominal_cents: Cents | None
    cumulative_debt_interest_cents: Cents | None
    debt_free_month: int | None
    starter_reserve_month: int | None
    full_reserve_month: int | None
    points: list[ProjectionPoint]
    # This projection's own allocator/state warnings (REPORT C3); the evaluation's
    # top-level warnings cover only state and the opening-month plan.
    warnings: list[str] = Field(default_factory=list)


class Projections(Strict):
    current: Projection
    adaptive: Projection
    custom: Projection | None


class GlidePathAnchor(Strict):
    years_to_retirement: float
    equity_weight: float


class ModelAssumptions(Strict):
    annual_equity_return: float
    annual_bond_return: float
    annual_cash_return: float
    annual_inflation: float
    annual_salary_growth: float
    annual_living_cost_growth: float
    annual_employee_limit_growth: float
    high_interest_apr_threshold: float
    retirement_total_saving_target: float
    critical_reserve_cap_cents: Cents
    starter_reserve_months: float
    full_reserve_months: float
    returns_net_of_fees: bool
    glide_path: list[GlidePathAnchor]
    limitations: list[str]


# --- AI decision and explanation ---------------------------------------------


class Rationale(Strict):
    priority: str
    summary: str
    evidence_paths: list[str]
    tradeoff: str


class ConstraintCheck(Strict):
    code: str
    passed: bool


class RecommendationProposal(Strict):
    """Internal: what the Recommendation Agent returns, before Python validation."""

    model_id: str
    ordered_priorities: list[str]
    rationale: list[Rationale]


class DecisionSummary(Strict):
    decision_id: str
    source: Literal["ai", "rules_fallback"]
    model_id: str | None
    prompt_version: str
    ordered_priorities: list[Priority]
    rationale: list[Rationale]
    constraint_checks: list[ConstraintCheck]
    fallback_reason: str | None


class Change(Strict):
    field_path: str
    before: Scalar
    after: Scalar


class AIExplanation(Strict):
    state_summary: str
    narrative: str
    source: Literal["ai", "template"]
    changes: list[Change]


# --- Evaluation ----------------------------------------------------------------


class EvaluationCore(Strict):
    """Everything the engine produces; the API adds decision_summary and explanation."""

    schema_version: str
    model_version: str
    policy_version: str
    profile_id: str
    input_hash: str
    financial_state: FinancialState
    plan: Plan
    assumptions: ModelAssumptions
    projections: Projections
    warnings: list[str]


class Evaluation(EvaluationCore):
    decision_summary: DecisionSummary
    explanation: AIExplanation


# --- Other responses -------------------------------------------------------------


class Health(Strict):
    status: Literal["ok"]
    schema_version: str
    model_version: str
    policy_version: str
    plaid_enabled: bool
    ai_available: bool


class DemoProfiles(Strict):
    schema_version: str
    profiles: list[FinancialProfile]


class ErrorBody(Strict):
    code: str
    message: str
    field_paths: list[str]
    retryable: bool


class ErrorEnvelope(Strict):
    error: ErrorBody
