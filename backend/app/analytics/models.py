"""Wire models for the scenario-history API. Money is integer cents, like the rest of the contract."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Literal

from pydantic import Field

from app.schemas import Cents, DecisionSummary, PlanningPreference, Scenario, Strict

Strategy = Literal["current", "adaptive", "custom"]
HORIZON_YEARS = (5, 10, 20)


class SaveRunRequest(Strict):
    """What the app saves: the inputs of a result it is showing, never its numbers.

    The server re-runs the engine from these inputs and stores only its own output.
    `input_hash` must match the recomputed hash, which proves the stored run is the
    result the user saw.
    """

    profile_id: str = Field(min_length=1, max_length=64)
    scenario: Scenario | None = None
    decision_summary: DecisionSummary
    input_hash: str = Field(min_length=1, max_length=128)
    planning_preference: PlanningPreference | None = None  # the plan style the app applied, if any


class RunSummary(Strict):
    run_id: str
    profile_id: str
    label: str
    created_at: datetime
    as_of_date: date
    scenario: Scenario | None
    primary_strategy: Strategy
    retirement_age: int
    final_retirement_balance_cents: Cents | None
    decision_source: Literal["ai", "rules_fallback"]
    model_id: str | None
    prompt_version: str
    model_version: str
    policy_version: str
    input_hash: str


class SaveRunResponse(Strict):
    run: RunSummary
    created: bool


class RunList(Strict):
    runs: list[RunSummary]


class YearValues(Strict):
    retirement_balance_cents: Cents
    cash_cents: Cents
    debt_cents: Cents


class ComparisonYear(Strict):
    year: int
    month: int
    projected_on: date
    base: YearValues | None
    other: YearValues | None


class Horizon(Strict):
    years: int
    month: int
    projected_on: date
    base: YearValues | None
    other: YearValues | None


class Comparison(Strict):
    profile_id: str
    as_of_date: date
    base: RunSummary
    other: RunSummary
    years: list[ComparisonYear]
    horizons: list[Horizon]
    source: Literal["tiger_data"]
    method: str


class HistoryStatus(Strict):
    enabled: bool
    available: bool


@dataclass(frozen=True)
class PointRow:
    strategy: str
    month: int
    projected_on: date
    retirement_balance_cents: int
    cash_cents: int
    debt_cents: int


@dataclass(frozen=True)
class YearRow:
    """One row of the yearly roll-up: the point at month 12 * bucket_year of a run's strategy."""

    run_id: str
    strategy: str
    month: int
    projected_on: date
    retirement_balance_cents: int
    cash_cents: int
    debt_cents: int


@dataclass(frozen=True)
class RunRecord:
    """A run ready to store: summary fields plus every projection point."""

    run_id: str
    profile_id: str
    label: str
    as_of_date: date
    scenario: Scenario | None
    primary_strategy: str
    retirement_age: int
    final_retirement_balance_cents: int | None
    decision_source: str
    model_id: str | None
    prompt_version: str
    ordered_priorities: list[str]
    schema_version: str
    model_version: str
    policy_version: str
    input_hash: str
    assumptions: dict
    points: list[PointRow]
    owner: str | None = None  # SHA-256 of the user's profile key; None for shared demo runs
