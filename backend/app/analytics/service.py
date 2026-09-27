"""Scenario history logic with no database code: rebuild a run from its inputs, and compare two runs.

Month m of a projection is dated the first day of the calendar month m months after the
profile's `as_of_date` month. This is the same rule the apps use for labels (`monthLabel`).
These are projected dates for a hypothetical plan, not observed market data.

A run's "year y" is the point at month 12 * y, which is how the desktop chart samples a
projection (`balanceAtYear`). The yearly roll-up in the database uses the same rule.
"""
from __future__ import annotations

import uuid
from datetime import date

from app import engine_port as engine
from app.analytics.models import (
    HORIZON_YEARS, Comparison, ComparisonYear, Horizon, PointRow, RunRecord, RunSummary, YearRow, YearValues,
)
from app.errors import ApiError
from app.schemas import DecisionSummary, FinancialProfile, RecommendationProposal, Scenario

METHOD = ("Yearly values from the projection_yearly continuous aggregate: "
          "time_bucket(12, month) with first(value, month) over the projection_point hypertable.")


def projected_date(as_of: date, month: int) -> date:
    absolute = as_of.month - 1 + month
    return date(as_of.year + absolute // 12, absolute % 12 + 1, 1)


def run_label(profile: FinancialProfile, scenario: Scenario | None) -> str:
    """Built on the server from the scenario, so no free text from the client is stored."""
    if scenario is None:
        return "Plan as is"
    rate = scenario.employee_contribution_rate
    contribution = "adaptive contribution" if rate is None else f"{rate * 100:g}% fixed contribution"
    return f"Retire at {scenario.retirement_age} · {contribution}"


def demo_profile(profile_id: str) -> FinancialProfile:
    for profile in engine.load_demo_profiles():
        if profile.id == profile_id:
            return profile
    raise ApiError(422, "INVALID_REQUEST", "Only the demo profiles can be saved to history.", ["profile_id"])


def revalidate(profile: FinancialProfile, decision: DecisionSummary) -> DecisionSummary:
    """Re-check the decision with the engine's validator; its order must survive unchanged."""
    state = engine.derive_state(profile)
    if decision.source == "ai":
        proposal = RecommendationProposal(
            model_id=decision.model_id or "",
            ordered_priorities=list(decision.ordered_priorities),
            rationale=decision.rationale,
        )
        checked = engine.validate_decision(profile, state, proposal, prompt_version=decision.prompt_version)
    else:
        checked = engine.validate_decision(profile, state, None, prompt_version=decision.prompt_version,
                                           fallback_reason=decision.fallback_reason)
    if checked.source != decision.source or checked.ordered_priorities != decision.ordered_priorities:
        raise ApiError(422, "INVALID_REQUEST", "This decision doesn't pass the engine's checks.",
                       ["decision_summary"])
    return checked


def build_run(body_profile_id: str, scenario: Scenario | None, decision: DecisionSummary,
              expected_hash: str) -> RunRecord:
    profile = demo_profile(body_profile_id)
    if scenario and scenario.retirement_age <= profile.age:
        raise ApiError(422, "INVALID_REQUEST", "Scenario retirement age must be greater than current age.",
                       ["scenario.retirement_age"])
    checked = revalidate(profile, decision)
    core = engine.evaluate(profile, scenario, checked)
    if core.input_hash != expected_hash:
        raise ApiError(409, "STALE_RESULT", "This result is out of date. Recalculate it, then save.",
                       ["input_hash"])

    projections = core.projections
    primary = "custom" if scenario else "adaptive"
    shown = projections.custom if scenario else projections.adaptive
    if shown is None or not shown.feasible:
        raise ApiError(422, "INFEASIBLE_SCENARIO", "Only scenarios that can be funded can be saved.",
                       ["scenario"])

    points = [
        PointRow(p.strategy, point.month, projected_date(profile.as_of_date, point.month),
                 point.retirement_balance_cents, point.cash_cents, point.debt_cents)
        for p in (projections.current, projections.adaptive, projections.custom)
        if p is not None and p.feasible
        for point in p.points
    ]
    return RunRecord(
        run_id=str(uuid.uuid4()),
        profile_id=profile.id,
        label=run_label(profile, scenario),
        as_of_date=profile.as_of_date,
        scenario=scenario,
        primary_strategy=primary,
        retirement_age=shown.retirement_age,
        final_retirement_balance_cents=shown.retirement_balance_nominal_cents,
        decision_source=checked.source,
        model_id=checked.model_id,
        prompt_version=checked.prompt_version,
        ordered_priorities=list(checked.ordered_priorities),
        schema_version=core.schema_version,
        model_version=core.model_version,
        policy_version=core.policy_version,
        input_hash=core.input_hash,
        assumptions=core.assumptions.model_dump(mode="json"),
        points=points,
    )


def yearly_reference(run_id: str, points: list[PointRow], strategy: str) -> list[YearRow]:
    """What the database roll-up must return for one strategy: the first point of each 12-month bucket."""
    buckets: dict[int, PointRow] = {}
    for p in sorted((p for p in points if p.strategy == strategy), key=lambda p: p.month):
        buckets.setdefault(p.month // 12, p)
    return [YearRow(run_id, strategy, p.month, p.projected_on, p.retirement_balance_cents, p.cash_cents,
                    p.debt_cents) for _, p in sorted(buckets.items())]


def _values(row: YearRow | None) -> YearValues | None:
    if row is None:
        return None
    return YearValues(retirement_balance_cents=row.retirement_balance_cents, cash_cents=row.cash_cents,
                      debt_cents=row.debt_cents)


def compare(base: RunSummary, other: RunSummary, base_rows: list[YearRow], other_rows: list[YearRow]) -> Comparison:
    if base.run_id == other.run_id:
        raise ApiError(422, "INVALID_REQUEST", "Choose two different runs.", ["other"])
    if base.profile_id != other.profile_id:
        raise ApiError(422, "INVALID_REQUEST", "Both runs must belong to the same profile.", ["other"])
    for rows in (base_rows, other_rows):
        if any(r.month % 12 for r in rows):  # the roll-up must only yield months 0, 12, 24, ...
            raise ValueError("yearly row is not on a 12-month boundary")

    a = {r.month // 12: r for r in base_rows}
    b = {r.month // 12: r for r in other_rows}
    last = max([*a, *b], default=-1)
    years = [
        ComparisonYear(year=y, month=12 * y, projected_on=projected_date(base.as_of_date, 12 * y),
                       base=_values(a.get(y)), other=_values(b.get(y)))
        for y in range(last + 1)
    ]
    horizons = [
        Horizon(years=h, month=12 * h, projected_on=projected_date(base.as_of_date, 12 * h),
                base=_values(a.get(h)), other=_values(b.get(h)))
        for h in HORIZON_YEARS
    ]
    return Comparison(profile_id=base.profile_id, as_of_date=base.as_of_date, base=base, other=other,
                      years=years, horizons=horizons, source="tiger_data", method=METHOD)
