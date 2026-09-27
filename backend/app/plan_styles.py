"""Plan-style comparison: one profile under each planning preference's own priority order.

The desktop guide and the "How your plan style compares" panel use this to show what each
style does. Each style runs through the engine with its default (rules) order, with no AI
call, so the three results differ only by style, come back in milliseconds and never count
against AI rate limits. /v1/evaluate is unchanged: there, AI may still choose any documented
order and the style is the default and fallback.
"""
from __future__ import annotations

from datetime import date
from typing import get_args

from fastapi import APIRouter, Request

from app import engine_port as engine
from app.ai.prompts import PROMPT_VERSION
from app.errors import ApiError
from app.schemas import (
    Cents, ErrorEnvelope, FinancialProfile, PlanningPreference, Priority, Projection, Strict,
)

router = APIRouter(prefix="/v1/plan-styles", tags=["plan styles"])

STYLES: tuple[str, ...] = get_args(PlanningPreference)
STYLE_LABELS = {
    "balanced": "Balanced",
    "cash_security": "Cash security first",
    "debt_reduction": "Debt payoff first",
}
CURRENT_LABEL = "Current habits"
METHOD = ("Each style's default priority order through the rules engine (no AI), expected-return "
          "assumptions. Yearly values are the projection points at months 0, 12, 24, ...")

_ERRORS = {code: {"model": ErrorEnvelope} for code in (422, 429)}


class YearPoint(Strict):
    year: int
    month: int
    retirement_balance_cents: Cents
    cash_cents: Cents
    debt_cents: Cents


class StyleOutcome(Strict):
    style: PlanningPreference | None  # None for current habits
    label: str
    ordered_priorities: list[Priority] | None
    retirement_age: int
    debt_free_month: int | None
    starter_reserve_month: int | None
    full_reserve_month: int | None
    cumulative_debt_interest_cents: Cents | None
    retirement_balance_nominal_cents: Cents | None
    retirement_balance_today_cents: Cents | None
    yearly: list[YearPoint]


class PlanStylesRequest(Strict):
    profile: FinancialProfile


class PlanStyles(Strict):
    profile_id: str
    as_of_date: date
    model_version: str
    policy_version: str
    current: StyleOutcome
    styles: list[StyleOutcome]
    method: str


def _outcome(projection: Projection, style: str | None, order: list[str] | None) -> StyleOutcome:
    return StyleOutcome(
        style=style,
        label=STYLE_LABELS[style] if style else CURRENT_LABEL,
        ordered_priorities=order,
        retirement_age=projection.retirement_age,
        debt_free_month=projection.debt_free_month,
        starter_reserve_month=projection.starter_reserve_month,
        full_reserve_month=projection.full_reserve_month,
        cumulative_debt_interest_cents=projection.cumulative_debt_interest_cents,
        retirement_balance_nominal_cents=projection.retirement_balance_nominal_cents,
        retirement_balance_today_cents=projection.retirement_balance_today_cents,
        yearly=[YearPoint(year=p.month // 12, month=p.month, retirement_balance_cents=p.retirement_balance_cents,
                          cash_cents=p.cash_cents, debt_cents=p.debt_cents)
                for p in projection.points if p.month % 12 == 0],
    )


def compare_styles(profile: FinancialProfile) -> PlanStyles:
    outcomes, current, core = [], None, None
    for style in STYLES:
        styled = profile.model_copy(update={"planning_preference": style})
        decision = engine.validate_decision(styled, engine.derive_state(styled), None, prompt_version=PROMPT_VERSION)
        core = engine.evaluate(styled, None, decision)
        outcomes.append(_outcome(core.projections.adaptive, style, list(decision.ordered_priorities)))
        if current is None:  # current habits don't depend on the style
            current = _outcome(core.projections.current, None, None)
    return PlanStyles(profile_id=profile.id, as_of_date=profile.as_of_date, model_version=core.model_version,
                      policy_version=core.policy_version, current=current, styles=outcomes, method=METHOD)


@router.post("", response_model=PlanStyles, responses=_ERRORS)
def plan_styles(body: PlanStylesRequest, request: Request) -> PlanStyles:
    if not request.app.state.evaluate_limiter.allow():
        raise ApiError(429, "RATE_LIMITED", "Too many requests. Try again in a minute.", retryable=True)
    return compare_styles(body.profile)
