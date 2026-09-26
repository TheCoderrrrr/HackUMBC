"""The only place the API layer touches the financial engine.

Developer A calls these functions. Developer B's engine (app/engine/) supplies
state, policy, validation and template explanations; it works on plain JSON-style
dicts, so this module converts to and from the Pydantic contract at the boundary.
Projections are still a temporary A-owned placeholder (`engine_stub`) until
Developer C's simulation and evaluator land.
"""
from __future__ import annotations

import json
from pathlib import Path

from app import engine_stub as _pending
from app.engine import assumptions as _assumptions
from app.engine import explanations as _explanations
from app.engine import policy as _policy
from app.engine import state as _state
from app.engine.validation import ProfileValidationError  # noqa: F401  (re-exported for the API)
from app.schemas import (
    AIExplanation,
    Change,
    DecisionSummary,
    EvaluationCore,
    FinancialProfile,
    FinancialState,
    ModelAssumptions,
    Plan,
    RecommendationProposal,
    Scenario,
)

MODEL_VERSION: str = _assumptions.MODEL_VERSION
POLICY_VERSION: str = _assumptions.POLICY_VERSION
BLOCKING_WARNINGS = ("MISSING_REQUIRED_INPUT", "CASH_FLOW_SHORTFALL")
_FIXTURES = Path(__file__).resolve().parent.parent / "fixtures" / "profiles.json"

State = dict  # Developer B's raw state dict; validate_decision requires it unchanged.


def _dump(profile: FinancialProfile) -> dict:
    return profile.model_dump(mode="json")


def load_demo_profiles() -> list[FinancialProfile]:
    return [FinancialProfile.model_validate(p) for p in json.loads(_FIXTURES.read_text(encoding="utf-8"))]


def derive_state(profile: FinancialProfile) -> State:
    """Raises ProfileValidationError (with .path) for inputs B's engine cannot plan."""
    return _state.derive_state(_dump(profile))


def blocking_issue(profile: FinancialProfile, state: State) -> str | None:
    return next((w for w in BLOCKING_WARNINGS if w in state["warnings"]), None)


def default_order(preference: str) -> list[str]:
    return list(_policy.default_priorities(preference))


def permitted_orders(profile: FinancialProfile) -> list[list[str]]:
    # The Morgan cash-security exception needs B's trusted opt-in and is shown only
    # through C's saved artifact, so live requests always use the preference default.
    return [default_order(profile.planning_preference)]


def agent_indicators(profile: FinancialProfile, state: State) -> dict:
    """B's allowlisted Recommendation context (no names or IDs)."""
    return _state.recommendation_context(_dump(profile), state)


def evidence_paths(indicators: dict) -> list[str]:
    """Flattened keys the Recommendation Agent may cite; mirrors B's evidence check."""
    top = [k for k, v in indicators.items() if k != "financial_state" and v is not None]
    nested = [f"financial_state.{k}" for k, v in indicators["financial_state"].items() if v is not None]
    return top + nested


def validate_decision(
    profile: FinancialProfile,
    state: State,
    proposal: RecommendationProposal | None,
    *,
    prompt_version: str,
    fallback_reason: str | None = None,
) -> DecisionSummary:
    raw = None
    if proposal is not None:
        raw = {"ordered_priorities": proposal.ordered_priorities,
               "rationale": [r.model_dump() for r in proposal.rationale]}
    decision = _policy.validate_decision(
        _dump(profile), state, raw,
        model_id=proposal.model_id if proposal else None,
        prompt_version=prompt_version,
    )
    # B reports a missing proposal generically; the provider wrapper knows the cause.
    if decision["fallback_reason"] == "NO_AI_PROPOSAL" and fallback_reason:
        decision["fallback_reason"] = fallback_reason
    return DecisionSummary.model_validate(decision)


def scenario_problem(
    profile: FinancialProfile, state: State, decision: DecisionSummary, scenario: Scenario | None
) -> str | None:
    """A message when a fixed custom election cannot be funded (maps to 422 INFEASIBLE_SCENARIO)."""
    if scenario is None or scenario.employee_contribution_rate is None:
        return None
    try:
        month = _policy.allocate_month(
            _dump(profile), state, decision.model_dump(mode="json"),
            strategy="custom", employee_contribution_rate=scenario.employee_contribution_rate,
        )
    except ValueError as exc:  # e.g. above the annual employee cap
        return str(exc)
    if not month["feasible"]:
        gap = month["shortfall_cents"] or 0
        return f"This contribution needs ${gap / 100:,.2f} more per month than the budget allows."
    return None


def evaluate(
    profile: FinancialProfile, state: State, scenario: Scenario | None, decision: DecisionSummary
) -> EvaluationCore:
    plan = _policy.build_plan(_dump(profile), state, decision.model_dump(mode="json"))
    return EvaluationCore(
        schema_version=_assumptions.SCHEMA_VERSION,
        model_version=MODEL_VERSION,
        policy_version=POLICY_VERSION,
        profile_id=profile.id,
        input_hash=_pending.input_hash(profile, scenario, decision),
        financial_state=FinancialState.model_validate(state),
        plan=Plan.model_validate(plan),
        assumptions=ModelAssumptions.model_validate(_assumptions.MODEL_ASSUMPTIONS),
        projections=_pending.pending_projections(profile, scenario),
        warnings=[_pending.STUB_WARNING],
    )


def template_explanation(
    profile: FinancialProfile, state: State, core: EvaluationCore, decision: DecisionSummary,
    changes: list[Change],
) -> AIExplanation:
    raw = _explanations.template_explanation(
        _dump(profile), state, decision.model_dump(mode="json"),
        core.plan.model_dump(mode="json"), changes=[c.model_dump() for c in changes],
    )
    return AIExplanation.model_validate(raw)
