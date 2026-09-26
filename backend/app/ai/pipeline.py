"""The /v1/evaluate orchestration (BACKEND.md section 9).

    state      = engine.derive_state          (Python, once per request)
    decision   = Recommendation Agent (AI) -> engine.validate_decision (Python)
    core       = engine.evaluate               (Python: plan, assumptions, projections)
    changes    = diff vs previous_decision_id  (Python)
    explanation= Explanation Agent (AI) or engine.template_explanation
    remember   = decision snapshot for the next previous_decision_id

Both AI calls share one hard deadline and never retry. Any AI failure falls back to
the rules order and/or template explanation, labeled honestly in the response. A
circuit breaker skips the provider while it is rate-limiting or timing out.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
import time
from dataclasses import dataclass

from app import engine_port as engine
from app.ai.breaker import AIBreaker
from app.ai.client import AIRateLimited, AITimeout, StructuredModel
from app.ai.prompts import SYSTEM, ExplanationOut, explanation_prompt, recommendation_prompt, recommendation_schema
from app.config import Settings
from app.decisions import DecisionSnapshot, DecisionStore, diff, snapshot_fields
from app.errors import ApiError
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
# Text values safe to show the model. Others (e.g. plan.primary_action_id) can embed
# debt IDs, so only their direction is described.
_SAFE_TEXT_FIELDS = {"planning_preference", "decision.ordered_priorities"}


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


def explanation_facts(profile, state, core: EvaluationCore, decision: DecisionSummary,
                      changes: list[Change], *, initial: bool) -> dict:
    """Everything the Explanation Agent may use: qualitative, no names, IDs or amounts."""
    return {
        "planning_preference": profile.planning_preference,
        "situation": situation_flags(profile, state),
        "ordered_priorities": decision.ordered_priorities,
        "rationale": [{"priority": r.priority, "summary": r.summary, "tradeoff": r.tradeoff}
                      for r in decision.rationale],
        "primary_action": next(({"category": a.category, "status": a.status} for a in core.plan.actions
                                if a.id == core.plan.primary_action_id), None),
        "actions": [{"category": a.category, "status": a.status, "reason_codes": a.reason_codes}
                    for a in core.plan.actions],
        "reason_codes": [r.code for r in core.plan.reasons],
        "is_initial_plan": initial,
        "changes": [describe_change(c) for c in changes],
    }


@dataclass
class _Request:
    """Per-request working state passed between pipeline steps."""

    profile: FinancialProfile
    state: dict
    deadline: float
    warnings: list[str]


class EvaluationPipeline:
    def __init__(self, settings: Settings, model: StructuredModel | None, store: DecisionStore,
                 breaker: AIBreaker | None = None, clock=time.monotonic):
        self.settings, self.model, self.store, self.clock = settings, model, store, clock
        self.breaker = breaker or AIBreaker(clock=clock)

    # --- orchestration -------------------------------------------------------------

    def run(self, request: EvaluateRequest) -> Evaluation:
        req = _Request(
            profile=request.profile,
            state=engine.derive_state(request.profile),
            deadline=self.clock() + self.settings.ai_total_timeout_seconds,
            warnings=[],
        )
        decision = self._decide(req)
        self._check_scenario(req, decision, request)
        core = engine.evaluate(req.profile, req.state, request.scenario, decision)
        previous = self._previous(req, request.previous_decision_id)
        current_fields = snapshot_fields(req.profile, core, decision)
        changes = diff(previous.fields, current_fields) if previous else []
        explanation = self._explanation(req, core, decision, changes, initial=previous is None)
        self.store.put(decision.decision_id, DecisionSnapshot(req.profile.id, profile_hash(req.profile), current_fields))
        return Evaluation(
            **core.model_dump(exclude={"warnings"}), warnings=core.warnings + req.warnings,
            decision_summary=decision, explanation=explanation,
        )

    # --- steps -----------------------------------------------------------------------

    def _decide(self, req: _Request) -> DecisionSummary:
        proposal, reason = None, None
        if engine.blocking_issue(req.profile, req.state):
            reason = None  # B's engine labels it BLOCKED_FINANCIAL_INPUT
        elif self.model is None:
            reason = "AI_UNAVAILABLE"
        elif self.breaker.is_open():
            reason = "AI_COOLDOWN"
        else:
            proposal, reason = self._recommend(req)
        return engine.validate_decision(
            req.profile, req.state, proposal,
            prompt_version=self.settings.ai_prompt_version, fallback_reason=reason,
        )

    def _check_scenario(self, req: _Request, decision: DecisionSummary, request: EvaluateRequest) -> None:
        problem = engine.scenario_problem(req.profile, req.state, decision, request.scenario)
        if problem:
            raise ApiError(422, "INFEASIBLE_SCENARIO", problem, ["scenario.employee_contribution_rate"])

    def _previous(self, req: _Request, decision_id: str | None):
        if not decision_id:
            return None
        previous = self.store.get(decision_id, req.profile.id)
        if previous is None:
            req.warnings.append(PREVIOUS_DECISION_NOT_FOUND)
        return previous

    def _explanation(self, req: _Request, core: EvaluationCore, decision: DecisionSummary,
                     changes: list[Change], *, initial: bool) -> AIExplanation:
        explanation = None
        if decision.source == "ai" and self.model is not None:
            if req.deadline - self.clock() < self.settings.ai_min_explanation_seconds:
                log.info("explanation skipped: not enough time left in the AI budget")
            else:
                facts = explanation_facts(req.profile, req.state, core, decision, changes, initial=initial)
                explanation = self._explain(facts, changes, req.deadline)
        return explanation or engine.template_explanation(req.profile, req.state, core, decision, changes)

    # --- provider calls ----------------------------------------------------------------

    def _call(self, name: str, prompt: str, schema, deadline: float):
        """One provider call inside the shared deadline; updates the breaker. Raises on failure."""
        started = self.clock()
        try:
            result = self.model.generate(SYSTEM, prompt, schema, deadline - self.clock())
        except AITimeout:
            self.breaker.record_timeout()
            raise
        except AIRateLimited as exc:
            self.breaker.record_rate_limited(exc.retry_after_s)
            raise
        finally:
            log.info("%s latency_ms=%d", name, int((self.clock() - started) * 1000))
        self.breaker.record_success()
        return result

    def _recommend(self, req: _Request) -> tuple[RecommendationProposal | None, str | None]:
        indicators = engine.agent_indicators(req.profile, req.state)
        keys = engine.evidence_paths(indicators)
        prompt = recommendation_prompt(req.profile.planning_preference, engine.permitted_orders(req.profile),
                                       indicators, keys)
        try:
            out, served_model = self._call("recommendation", prompt, recommendation_schema(keys), req.deadline)
        except AITimeout:
            return None, "TIMEOUT"
        except AIRateLimited:
            return None, "RATE_LIMITED"
        except Exception as exc:  # provider, network or malformed output
            log.warning("recommendation call failed: %s", type(exc).__name__)
            return None, "PROVIDER_ERROR"
        return RecommendationProposal(
            model_id=served_model or self.model.model_id,
            ordered_priorities=list(out.ordered_priorities),
            rationale=[Rationale(**r.model_dump()) for r in out.rationale],
        ), None

    def _explain(self, facts: dict, changes: list[Change], deadline: float) -> AIExplanation | None:
        try:
            out, _ = self._call("explanation", explanation_prompt(facts), ExplanationOut, deadline)
        except Exception as exc:  # timeout, rate limit, provider or malformed output
            log.warning("explanation call failed: %s", type(exc).__name__)
            return None
        if not valid_prose(out):
            log.warning("explanation rejected: unsupported numbers or length")
            return None
        return AIExplanation(state_summary=out.state_summary, narrative=out.narrative, source="ai", changes=changes)
