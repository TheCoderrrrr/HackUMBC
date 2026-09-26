"""The only place the API layer touches the financial engine.

Developer A calls these functions. Developer B's engine (app/engine/) supplies
state, policy, validation and template explanations; Developer C's evaluator
(app/engine/evaluate.py) supplies projections and the canonical input hash. Both
work on plain JSON-style dicts, so this module converts to and from the Pydantic
contract at the boundary.
"""
from __future__ import annotations

import json
from pathlib import Path

from app.engine import assumptions as _assumptions
from app.engine import explanations as _explanations
from app.engine import policy as _policy
from app.engine import state as _state
from app.engine.evaluate import evaluate as _evaluate
from app.engine.monthly import InfeasibleScenario
from app.engine.validation import ProfileValidationError  # noqa: F401  (re-exported for the API)
from app.errors import ApiError
from app.schemas import (
    AIExplanation,
    Change,
    DecisionSummary,
    EvaluationCore,
    FinancialProfile,
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


def evaluate(profile: FinancialProfile, scenario: Scenario | None, decision: DecisionSummary) -> EvaluationCore:
    try:
        evaluation = _evaluate(
            profile, scenario, decision,
            schema_version=_assumptions.SCHEMA_VERSION,
            model_version=MODEL_VERSION,
            policy_version=POLICY_VERSION,
        )
    except InfeasibleScenario as exc:
        raise ApiError(
            422, "INFEASIBLE_SCENARIO",
            f"This scenario is short ${exc.shortfall_cents / 100:,.2f} in month {exc.month}. "
            "Choose a lower contribution rate or a different retirement age.",
            ["scenario.employee_contribution_rate"],
        ) from exc
    return EvaluationCore.model_validate(
        evaluation.model_dump(exclude={"decision_summary", "explanation"})
    )


def template_explanation(
    profile: FinancialProfile, core: EvaluationCore, decision: DecisionSummary, changes: list[Change]
) -> AIExplanation:
    raw = _explanations.template_explanation(
        _dump(profile), derive_state(profile), decision.model_dump(mode="json"),
        core.plan.model_dump(mode="json"), changes=[c.model_dump() for c in changes],
    )
    return AIExplanation.model_validate(raw)
