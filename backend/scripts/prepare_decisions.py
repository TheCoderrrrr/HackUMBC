"""Prepare fixtures/decisions.json by calling the model for each saved item.

Fixture preparation for the offline bundle (BACKEND.md section 13). Uses A's
Gemini client, prompts and prose rules, and B's decision validator; C's
evaluator binds each explanation to its artifact's exact input hash. Records
are written without review marks: Developers A and B review them and set
"reviewers": ["A", "B"] before `scripts.export_demo` will accept them.

Run from backend with GEMINI_API_KEY in backend/.env:

    python -m scripts.prepare_decisions --output fixtures/decisions.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from app.ai.pipeline import valid_prose
from app.ai.prompts import SYSTEM, ExplanationOut, RecommendationOut, explanation_prompt, recommendation_prompt
from app.engine.assumptions import MODEL_ASSUMPTIONS
from app.engine.canonical import profile_hash
from app.engine.evaluate import evaluate
from app.engine.policy import default_priorities, validate_decision
from app.engine.state import derive_state, recommendation_context
from app.schemas import FinancialProfile, Scenario
from scripts.export_demo import (
    PROFILE_IDS, STANDARD_IDS, VARIANT_ID, _artifact_specs, _default_opening_rate,
)

# The one documented non-default order (BACKEND.md section 12).
VARIANT_ORDER = ["starter_reserve", "high_apr_debt", "full_reserve"]
CALL_TIMEOUT_S = 60.0


class PrepareError(RuntimeError):
    """The model did not produce an acceptable saved item within the attempts."""


def load_profiles(profiles_path: Path) -> dict[str, FinancialProfile]:
    standard = json.loads(profiles_path.read_text(encoding="utf-8"))
    variant = json.loads(profiles_path.with_name("morgan-cash-security-profile.json").read_text(encoding="utf-8"))
    profiles = {p["id"]: FinancialProfile.model_validate(p) for p in [*standard, variant]}
    if set(profiles) != set(PROFILE_IDS):
        raise PrepareError(f"expected profiles {PROFILE_IDS}, found {sorted(profiles)}")
    return profiles


def indicators(profile: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    """B's recommendation context, flattened so its keys are the valid evidence paths."""
    context = recommendation_context(profile, state)
    nested = context.pop("financial_state")
    return {**context, **{f"financial_state.{k}": v for k, v in nested.items()}}


def permitted_orders(profile: dict[str, Any]) -> list[list[str]]:
    orders = [list(default_priorities(profile["planning_preference"]))]
    if profile["id"] == VARIANT_ID and VARIANT_ORDER not in orders:
        orders.append(VARIANT_ORDER)
    return orders


def situation(values: dict[str, Any]) -> dict[str, bool]:
    cash, capture = values["emergency_cash_cents"], values["financial_state.match_capture_fraction"]
    return {
        "starter_reserve_funded": cash >= values["financial_state.starter_reserve_target_cents"],
        "full_reserve_funded": cash >= values["financial_state.full_reserve_target_cents"],
        "has_high_interest_debt": bool(values["financial_state.high_interest_debt_cents"]),
        "has_any_debt": values["financial_state.highest_debt_apr"] is not None,
        "captures_full_employer_match": capture is not None and capture >= 1,
    }


def _recommend(model, profile: dict[str, Any], prompt_version: str, attempts: int) -> dict[str, Any]:
    state = derive_state(profile)
    values = indicators(profile, state)
    orders = permitted_orders(profile)
    required = VARIANT_ORDER if profile["id"] == VARIANT_ID else orders[0]
    prompt = recommendation_prompt(profile["planning_preference"], orders, values)
    problem = None
    for _ in range(attempts):
        try:
            out, served = model.generate(SYSTEM, prompt, RecommendationOut, CALL_TIMEOUT_S)
        except Exception as exc:  # provider or malformed output: retry during preparation
            problem = f"model call failed: {type(exc).__name__}"
            continue
        proposal = {"ordered_priorities": list(out.ordered_priorities),
                    "rationale": [r.model_dump() for r in out.rationale]}
        model_id = served or model.model_id
        decision = validate_decision(profile, state, proposal, model_id=model_id, prompt_version=prompt_version)
        if decision["source"] != "ai":
            problem = f"validator rejected proposal: {decision['fallback_reason']}"
        elif decision["ordered_priorities"] != required:
            problem = f"model chose {decision['ordered_priorities']}, saved item needs {required}"
        else:
            return {"proposal": proposal, "model_id": model_id, "decision": decision}
    raise PrepareError(f"{profile['id']}: no acceptable recommendation after {attempts} attempts ({problem})")


def _explain(model, profile: dict[str, Any], core: dict[str, Any], decision: dict[str, Any], attempts: int) -> dict[str, Any]:
    """Mirror A's live Explanation facts for an initial plan, without identifiers."""
    plan = core["plan"]
    primary = next(a for a in plan["actions"] if a["id"] == plan["primary_action_id"])
    facts = {
        "planning_preference": profile["planning_preference"],
        "situation": situation(indicators(profile, derive_state(profile))),
        "ordered_priorities": decision["ordered_priorities"],
        "rationale": [{"priority": r["priority"], "summary": r["summary"], "tradeoff": r["tradeoff"]}
                      for r in decision["rationale"]],
        "primary_action": {"category": primary["category"], "status": primary["status"]},
        "actions": [{"category": a["category"], "status": a["status"], "reason_codes": a["reason_codes"]}
                    for a in plan["actions"]],
        "reason_codes": [r["code"] for r in plan["reasons"]],
        "is_initial_plan": True,
        "changes": [],
    }
    problem = None
    for _ in range(attempts):
        try:
            out, _ = model.generate(SYSTEM, explanation_prompt(facts), ExplanationOut, CALL_TIMEOUT_S)
        except Exception as exc:
            problem = f"model call failed: {type(exc).__name__}"
            continue
        if valid_prose(out):
            return {"state_summary": out.state_summary, "narrative": out.narrative, "source": "ai", "changes": []}
        problem = "prose contained numbers or exceeded length limits"
    raise PrepareError(f"{profile['id']}: no acceptable explanation after {attempts} attempts ({problem})")


def prepare(model, profiles_path: Path, *, prompt_version: str, attempts: int = 3) -> dict[str, Any]:
    profiles = load_profiles(profiles_path)
    records: dict[str, Any] = {}
    decisions: dict[str, dict[str, Any]] = {}
    for profile_id in PROFILE_IDS:
        data = profiles[profile_id].model_dump(mode="json")
        result = _recommend(model, data, prompt_version, attempts)
        decision_id = f"dec_saved_{profile_id}"
        decisions[profile_id] = {**result["decision"], "decision_id": decision_id}
        records[profile_id] = {
            "profile_hash": profile_hash(profiles[profile_id]),
            "proposal": result["proposal"],
            "model_id": result["model_id"],
            "prompt_version": prompt_version,
            "decision_id": decision_id,
            "expected_source": "ai",
            "reviewers": [],
        }

    rates = {pid: _default_opening_rate(profiles[pid], MODEL_ASSUMPTIONS, decisions[pid]) for pid in STANDARD_IDS}
    explanations: dict[str, Any] = {}
    for profile_id, preset_id, _filename, scenario in _artifact_specs(profiles, rates, Scenario):
        core = evaluate(profiles[profile_id], scenario, decisions[profile_id]).model_dump(mode="json")
        explanation = _explain(model, profiles[profile_id].model_dump(mode="json"), core,
                               decisions[profile_id], attempts)
        explanations[core["input_hash"]] = {
            "artifact": f"{profile_id}/{preset_id}",  # for reviewers; the exporter keys on the hash
            "explanation": explanation,
            "reviewers": [],
        }

    fallback_cases = [{
        "profile_id": profile_id,
        "profile_hash": profile_hash(profiles[profile_id]),
        "proposal": None,
        "model_id": None,
        "prompt_version": prompt_version,
        "decision_id": f"dec_fallback_{profile_id}",
        "expected_source": "rules_fallback",
        "reviewers": [],
    } for profile_id in PROFILE_IDS]
    return {"decisions": records, "explanations": explanations, "fallback_cases": fallback_cases}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profiles", type=Path, default=Path("fixtures/profiles.json"))
    parser.add_argument("--output", type=Path, default=Path("fixtures/decisions.json"))
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--force", action="store_true", help="replace an existing decisions file")
    args = parser.parse_args()
    if args.output.exists() and not args.force:
        parser.exit(1, f"{args.output} exists; pass --force to replace it (this discards review marks)\n")

    from app.ai.client import GeminiModel
    from app.config import load_settings

    settings = load_settings()
    if not settings.gemini_api_key:
        parser.exit(1, "GEMINI_API_KEY is not set in backend/.env\n")
    model = GeminiModel(settings.gemini_api_key, settings.ai_model, settings.ai_thinking_level)
    try:
        fixture = prepare(model, args.profiles, prompt_version=settings.ai_prompt_version, attempts=args.attempts)
    except PrepareError as exc:
        parser.exit(1, f"prepare failed: {exc}\n")
    args.output.write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {len(fixture['decisions'])} decisions and {len(fixture['explanations'])} explanations "
          f"to {args.output}; send it to A and B for review")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
