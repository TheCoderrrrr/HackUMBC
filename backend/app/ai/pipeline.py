"""The /v1/evaluate orchestration (BACKEND.md section 9).

1. derive state (Python)            4. evaluate plan + projections (Python)
2. Recommendation Agent (AI)        5. Explanation Agent (AI), or templates
3. validate_decision (Python)       6. remember the decision for previous_decision_id

Both AI calls share one hard deadline and never retry. Any AI failure falls back to
the rules order and/or template explanation, labeled honestly in the response.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
import time

from app import engine_port as engine
from app.ai.client import AITimeout, StructuredModel
from app.ai.prompts import SYSTEM, ExplanationOut, explanation_prompt, recommendation_prompt, recommendation_schema
from app.config import Settings
from app.decisions import DecisionSnapshot, DecisionStore, diff, snapshot_fields
from app.schemas import (
    AIExplanation,
    Change,
    DecisionSummary,
    EvaluateRequest,
    Evaluation,
    EvaluationCore,
    FinancialProfile,
    Rationale,
    RecommendationProposal,
)

log = logging.getLogger("adaptive_retirement")

PREVIOUS_DECISION_NOT_FOUND = "PREVIOUS_DECISION_NOT_FOUND"
_FORBIDDEN_IN_PROSE = re.compile(r"[0-9$%]")
_NUMBER_WORDS = re.compile(
    r"\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|"
    r"sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|"
    r"thousand|million|billion|percent|percentage|dollars?|cents?|half|quarter|double|triple|twice)\b",
    re.IGNORECASE,
)


def profile_hash(profile: FinancialProfile) -> str:
    canonical = json.dumps(profile.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def valid_prose(out: ExplanationOut) -> bool:
    for text, limit in ((out.state_summary, 400), (out.narrative, 900)):
        if not text.strip() or len(text) > limit:
            return False
        if _FORBIDDEN_IN_PROSE.search(text) or _NUMBER_WORDS.search(text):
            return False
    return True


# Text values safe to show the model. Others (e.g. plan.primary_action_id) can embed
# debt IDs, so only their direction is described.
_SAFE_TEXT_FIELDS = {"planning_preference", "decision.ordered_priorities"}


def describe_change(change: Change) -> dict[str, str]:
    """A number-free description of a change, so the model can explain direction without amounts."""
    before, after = change.before, change.after
    if isinstance(before, (int, float)) and isinstance(after, (int, float)) and not isinstance(before, bool):
        direction = "increased" if after > before else "decreased"
    elif before is None:
        direction = "was added"
    elif isinstance(after, str) and isinstance(before, str) and change.field_path in _SAFE_TEXT_FIELDS:
        direction = f"changed from {before} to {after}"
    else:
        direction = "changed"
    return {"field": change.field_path, "change": direction}


def situation_flags(profile: FinancialProfile, state: dict) -> dict[str, bool]:
    """Qualitative state for the Explanation Agent, derived from Python-computed state."""
    cash = profile.emergency_cash_cents
    capture = state["match_capture_fraction"]
    return {
        "starter_reserve_funded": cash >= state["starter_reserve_target_cents"],
        "full_reserve_funded": cash >= state["full_reserve_target_cents"],
        "has_high_interest_debt": state["high_interest_debt_cents"] > 0,
        "has_any_debt": state["highest_debt_apr"] is not None,
        "captures_full_employer_match": capture is not None and capture >= 1,
    }


class EvaluationPipeline:
    def __init__(self, settings: Settings, model: StructuredModel | None, store: DecisionStore, clock=time.monotonic):
        self.settings, self.model, self.store, self.clock = settings, model, store, clock

    def run(self, request: EvaluateRequest) -> Evaluation:
        profile = request.profile
        deadline = self.clock() + self.settings.ai_total_timeout_seconds
        state = engine.derive_state(profile)
        blocked = engine.blocking_issue(profile, state)

        proposal, fallback_reason = None, None
        if blocked:
            fallback_reason = None  # B's engine labels it BLOCKED_FINANCIAL_INPUT
        elif self.model is None:
            fallback_reason = "AI_UNAVAILABLE"
        else:
            proposal, fallback_reason = self._recommend(profile, state, deadline)

        decision = engine.validate_decision(
            profile, state, proposal,
            prompt_version=self.settings.ai_prompt_version,
            fallback_reason=fallback_reason,
        )
        core = engine.evaluate(profile, request.scenario, decision)

        warnings = list(core.warnings)
        previous = None
        if request.previous_decision_id:
            previous = self.store.get(request.previous_decision_id, profile.id)
            if previous is None:
                warnings.append(PREVIOUS_DECISION_NOT_FOUND)
        current_fields = snapshot_fields(profile, core, decision)
        changes = diff(previous.fields, current_fields) if previous else []

        explanation = None
        if decision.source == "ai" and self.model is not None:
            flags = situation_flags(profile, state)
            explanation = self._explain(profile, core, decision, changes, flags,
                                        initial=previous is None, deadline=deadline)
        if explanation is None:
            explanation = engine.template_explanation(profile, core, decision, changes)

        self.store.put(decision.decision_id, DecisionSnapshot(profile.id, profile_hash(profile), current_fields))
        return Evaluation(
            **core.model_dump(exclude={"warnings"}), warnings=warnings,
            decision_summary=decision, explanation=explanation,
        )

    def _recommend(self, profile, state, deadline) -> tuple[RecommendationProposal | None, str | None]:
        indicators = engine.agent_indicators(profile, state)
        keys = engine.evidence_paths(indicators)
        prompt = recommendation_prompt(profile.planning_preference, engine.permitted_orders(profile), indicators, keys)
        started = self.clock()
        try:
            out, served_model = self.model.generate(SYSTEM, prompt, recommendation_schema(keys), deadline - self.clock())
        except AITimeout:
            return None, "TIMEOUT"
        except Exception as exc:  # provider, network or malformed output
            log.warning("recommendation call failed: %s", type(exc).__name__)
            return None, "PROVIDER_ERROR"
        finally:
            log.info("recommendation latency_ms=%d", int((self.clock() - started) * 1000))
        return RecommendationProposal(
            model_id=served_model or self.model.model_id,
            ordered_priorities=list(out.ordered_priorities),
            rationale=[Rationale(**r.model_dump()) for r in out.rationale],
        ), None

    def _explain(self, profile, core: EvaluationCore, decision: DecisionSummary, changes: list[Change],
                 flags: dict[str, bool], *, initial: bool, deadline: float) -> AIExplanation | None:
        facts = {
            "planning_preference": profile.planning_preference,
            "situation": flags,
            "ordered_priorities": decision.ordered_priorities,
            "rationale": [{"priority": r.priority, "summary": r.summary, "tradeoff": r.tradeoff} for r in decision.rationale],
            "primary_action": next(({"category": a.category, "status": a.status} for a in core.plan.actions
                                    if a.id == core.plan.primary_action_id), None),
            "actions": [{"category": a.category, "status": a.status, "reason_codes": a.reason_codes} for a in core.plan.actions],
            "reason_codes": [r.code for r in core.plan.reasons],
            "is_initial_plan": initial,
            "changes": [describe_change(c) for c in changes],
        }
        started = self.clock()
        try:
            out, _ = self.model.generate(SYSTEM, explanation_prompt(facts), ExplanationOut, deadline - self.clock())
        except AITimeout:
            return None
        except Exception as exc:
            log.warning("explanation call failed: %s", type(exc).__name__)
            return None
        finally:
            log.info("explanation latency_ms=%d", int((self.clock() - started) * 1000))
        if not valid_prose(out):
            log.warning("explanation rejected: unsupported numbers or length")
            return None
        return AIExplanation(state_summary=out.state_summary, narrative=out.narrative, source="ai", changes=changes)
