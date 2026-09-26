"""TEMPORARY placeholder for Developer C's simulation and evaluator (A-owned).

Plans now come from Developer B's real engine. Only projections and the input hash
are placeholders: projections use the blocked shape from BACKEND.md section 5, and
every evaluation carries STUB_WARNING. Delete this module when C's evaluator lands.
"""
from __future__ import annotations

import hashlib
import json

from app.schemas import DecisionSummary, FinancialProfile, Projection, Projections, Scenario

STUB_WARNING = "STUB_PROJECTIONS: projections are placeholders until the simulation engine lands."


def _pending(strategy: str, retirement_age: int) -> Projection:
    return Projection(
        strategy=strategy, retirement_age=retirement_age, feasible=False, shortfall_cents=None,
        retirement_balance_nominal_cents=None, retirement_balance_today_cents=None,
        cash_nominal_cents=None, debt_nominal_cents=None, cumulative_debt_interest_cents=None,
        debt_free_month=None, starter_reserve_month=None, full_reserve_month=None, points=[],
    )


def pending_projections(profile: FinancialProfile, scenario: Scenario | None) -> Projections:
    return Projections(
        current=_pending("current", profile.retirement_age),
        adaptive=_pending("adaptive", profile.retirement_age),
        custom=_pending("custom", scenario.retirement_age) if scenario else None,
    )


def input_hash(profile: FinancialProfile, scenario: Scenario | None, decision: DecisionSummary) -> str:
    payload = json.dumps(
        {"profile": profile.model_dump(mode="json"),
         "scenario": scenario.model_dump(mode="json") if scenario else None,
         "order": decision.ordered_priorities, "preference": profile.planning_preference,
         "model": decision.model_id, "prompt": decision.prompt_version},
        sort_keys=True, separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode()).hexdigest()
