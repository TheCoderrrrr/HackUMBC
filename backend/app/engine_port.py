"""The only place the API layer touches the financial engine.

Developer A calls these functions; Developer B (state/policy) and Developer C
(simulation/evaluate) implement them. Until their modules land, `engine_stub`
provides placeholder implementations with the same signatures.

To switch to the real engine, replace the import below with the real modules and
keep the names exported here unchanged. The API never duplicates financial rules.
"""
from __future__ import annotations

from app import engine_stub as _engine

# Versions reported by /health and every Evaluation.
MODEL_VERSION: str = _engine.MODEL_VERSION
POLICY_VERSION: str = _engine.POLICY_VERSION

# load_demo_profiles() -> list[FinancialProfile]
load_demo_profiles = _engine.load_demo_profiles

# derive_state(profile) -> FinancialState                              [Developer B]
derive_state = _engine.derive_state

# blocking_issue(profile, state) -> str | None                         [Developer B]
# A reason code when the profile cannot be planned (cash shortfall, missing input);
# the API then skips AI and returns the blocked evaluation.
blocking_issue = _engine.blocking_issue

# default_order(planning_preference) -> list[Priority]              [Developer B]
default_order = _engine.default_order

# permitted_orders(profile) -> list[list[Priority]]                     [Developer B]
# Orders the Recommendation Agent may propose; the first is the policy default.
# The prompt, validate_decision and the fallback all use this one source.
permitted_orders = _engine.permitted_orders

# agent_indicators(profile, state) -> dict[str, float | int | None]    [Developer B]
# Python-computed liquidity, debt burden, savings capacity and horizon sent to the
# Recommendation Agent. Keys double as the allowed evidence paths.
agent_indicators = _engine.agent_indicators

# validate_decision(profile, state, proposal, *, decision_id, prompt_version,
#                   fallback_reason) -> DecisionSummary                [Developer B]
# proposal is None (or fails validation) -> rules fallback order.
validate_decision = _engine.validate_decision

# evaluate(profile, scenario, decision) -> EvaluationCore              [Developer C]
evaluate = _engine.evaluate

# template_explanation(profile, core, decision, changes) -> AIExplanation   [Developer B]
template_explanation = _engine.template_explanation
