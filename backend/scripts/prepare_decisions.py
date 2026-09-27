"""Prepare fixtures/decisions.json by calling the model for each saved item.

Fixture preparation for the offline bundle (BACKEND.md section 13). Uses A's
model client (AI_PROVIDER in backend/.env; GPT-6 Luna by default), prompts,
Explanation facts and prose rules, and B's decision validator; C's evaluator
binds each explanation to its artifact's exact input hash. The saved AI text
is demo placeholder content; edit it later if needed, then re-run the export.

Run from backend with the provider's key (OPENAI_API_KEY by default) in backend/.env:

    python -m scripts.prepare_decisions --output fixtures/decisions.json
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any, Callable

from app.ai.client import AIRateLimited
from app.ai.pipeline import explanation_facts, valid_prose
from app.ai.prompts import (
    PROMPT_VERSION, SYSTEM, ExplanationOut, explanation_prompt, recommendation_prompt, recommendation_schema,
)
from app.engine.assumptions import MODEL_ASSUMPTIONS
from app.engine.canonical import profile_hash
from app.engine.evaluate import evaluate
from app.engine.policy import default_priorities, validate_decision
from app.engine.state import derive_state, recommendation_context
from app.engine_port import evidence_paths, permitted_orders
from app.schemas import Evaluation, FinancialProfile, Scenario
from scripts.export_demo import (
    PROFILE_IDS, STANDARD_IDS, VARIANT_ID, _artifact_specs, _default_opening_rate,
)

# The one documented non-default order (BACKEND.md section 12).
VARIANT_ORDER = ["starter_reserve", "high_apr_debt", "full_reserve"]
CALL_TIMEOUT_S = 60.0
# Wait suggested by the provider after a rate limit, or this fallback, capped.
RATE_LIMIT_FALLBACK_S = 30.0
RATE_LIMIT_MAX_WAIT_S = 120.0


class PrepareError(RuntimeError):
    """The model did not produce an acceptable saved item within the attempts."""


def load_profiles(profiles_path: Path) -> dict[str, FinancialProfile]:
    standard = json.loads(profiles_path.read_text(encoding="utf-8"))
    variant = json.loads(profiles_path.with_name("morgan-cash-security-profile.json").read_text(encoding="utf-8"))
    profiles = {p["id"]: FinancialProfile.model_validate(p) for p in [*standard, variant]}
    if set(profiles) != set(PROFILE_IDS):
        raise PrepareError(f"expected profiles {PROFILE_IDS}, found {sorted(profiles)}")
    return profiles


def required_order(profile: dict[str, Any]) -> list[str]:
    """Saved standard decisions keep the preference default so the demo arithmetic holds
    (BACKEND.md section 12); only the Morgan variant demonstrates a different order."""
    return VARIANT_ORDER if profile["id"] == VARIANT_ID else list(default_priorities(profile["planning_preference"]))


def _generate(model, prompt: str, schema, sleep: Callable[[float], None]):
    """One model call. Returns (output, served_model) or a problem string to retry on."""
    try:
        return model.generate(SYSTEM, prompt, schema, CALL_TIMEOUT_S), None
    except AIRateLimited as exc:
        wait = min(exc.retry_after_s or RATE_LIMIT_FALLBACK_S, RATE_LIMIT_MAX_WAIT_S)
        print(f"rate limited; waiting {wait:.0f}s before the next attempt", flush=True)
        sleep(wait)
        return None, "model call failed: AIRateLimited"
    except Exception as exc:  # provider or malformed output: retry during preparation
        return None, f"model call failed: {type(exc).__name__}"


def _recommend(model, profile: dict[str, Any], attempts: int, sleep: Callable[[float], None]) -> dict[str, Any]:
    state = derive_state(profile)
    required = required_order(profile)
    # Same prompt and evidence-key schema as A's live pipeline.
    context = recommendation_context(profile, state)
    keys = evidence_paths(context)
    orders = permitted_orders(FinancialProfile.model_validate(profile))  # A's live list, default first
    prompt = recommendation_prompt(profile["planning_preference"], orders, context, keys)
    schema = recommendation_schema(keys)
    problem = None
    for _ in range(attempts):
        result, problem = _generate(model, prompt, schema, sleep)
        if result is None:
            continue
        out, served = result
        proposal = {"ordered_priorities": list(out.ordered_priorities),
                    "rationale": [r.model_dump() for r in out.rationale]}
        model_id = served or model.model_id
        decision = validate_decision(profile, state, proposal, model_id=model_id, prompt_version=PROMPT_VERSION)
        if decision["source"] != "ai":
            problem = f"validator rejected proposal: {decision['fallback_reason']}"
        elif decision["ordered_priorities"] != required:
            problem = f"model chose {decision['ordered_priorities']}, saved item needs {required}"
        else:
            return {"proposal": proposal, "model_id": model_id, "decision": decision}
    raise PrepareError(f"{profile['id']}: no acceptable recommendation after {attempts} attempts ({problem})")


def saved_explanation_facts(profile: FinancialProfile, evaluation: Evaluation) -> dict[str, Any]:
    """A's live Explanation facts for an initial plan, so saved prompts match live ones."""
    state = derive_state(profile.model_dump(mode="json"))
    return explanation_facts(profile, state, evaluation, evaluation.decision_summary, [], initial=True)


def _explain(model, profile: FinancialProfile, evaluation: Evaluation, attempts: int,
             sleep: Callable[[float], None]) -> dict[str, Any]:
    facts = saved_explanation_facts(profile, evaluation)
    problem = None
    for _ in range(attempts):
        result, problem = _generate(model, explanation_prompt(facts), ExplanationOut, sleep)
        if result is None:
            continue
        out, _ = result
        if valid_prose(out):
            return {"state_summary": out.state_summary, "narrative": out.narrative, "source": "ai", "changes": []}
        problem = "prose contained numbers or exceeded length limits"
    raise PrepareError(f"{profile.id}: no acceptable explanation after {attempts} attempts ({problem})")


def prepare(model, profiles_path: Path, *, attempts: int = 3,
            sleep: Callable[[float], None] = time.sleep) -> dict[str, Any]:
    profiles = load_profiles(profiles_path)
    records: dict[str, Any] = {}
    decisions: dict[str, dict[str, Any]] = {}
    for profile_id in PROFILE_IDS:
        data = profiles[profile_id].model_dump(mode="json")
        result = _recommend(model, data, attempts, sleep)
        decision_id = f"dec_saved_{profile_id}"
        decisions[profile_id] = {**result["decision"], "decision_id": decision_id}
        records[profile_id] = {
            "profile_hash": profile_hash(profiles[profile_id]),
            "proposal": result["proposal"],
            "model_id": result["model_id"],
            "prompt_version": PROMPT_VERSION,
            "decision_id": decision_id,
            "expected_source": "ai",
        }

    rates = {pid: _default_opening_rate(profiles[pid], MODEL_ASSUMPTIONS, decisions[pid]) for pid in STANDARD_IDS}
    explanations: dict[str, Any] = {}
    for profile_id, preset_id, _filename, scenario in _artifact_specs(profiles, rates, Scenario):
        evaluation = evaluate(profiles[profile_id], scenario, decisions[profile_id])
        explanation = _explain(model, profiles[profile_id], evaluation, attempts, sleep)
        explanations[evaluation.input_hash] = {
            "artifact": f"{profile_id}/{preset_id}",  # for people reading the file; the exporter keys on the hash
            "explanation": explanation,
        }

    fallback_cases = [{
        "profile_id": profile_id,
        "profile_hash": profile_hash(profiles[profile_id]),
        "proposal": None,
        "model_id": None,
        "prompt_version": PROMPT_VERSION,
        "decision_id": f"dec_fallback_{profile_id}",
        "expected_source": "rules_fallback",
    } for profile_id in PROFILE_IDS]
    return {"decisions": records, "explanations": explanations, "fallback_cases": fallback_cases}


def model_from_settings():
    """A's client for AI_PROVIDER in backend/.env, or an error message saying what is missing."""
    from dotenv import load_dotenv

    from app.ai.client import build_model
    from app.config import load_settings

    # This script needs the real key; the library modules no longer load .env (REPORT C7).
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")
    settings = load_settings()
    model = build_model(settings)
    if model is not None:
        return model
    if not settings.ai_enabled:
        return "AI_ENABLED is false in backend/.env; saved decisions need the model"
    key = "OPENAI_API_KEY" if settings.ai_provider == "openai" else "GEMINI_API_KEY"
    return f"{key} is not set in backend/.env (AI_PROVIDER={settings.ai_provider})"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profiles", type=Path, default=Path("fixtures/profiles.json"))
    parser.add_argument("--output", type=Path, default=Path("fixtures/decisions.json"))
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--force", action="store_true", help="replace an existing decisions file")
    args = parser.parse_args()
    if args.output.exists() and not args.force:
        parser.exit(1, f"{args.output} exists; pass --force to replace it (this discards any edits to the saved text)\n")

    model = model_from_settings()
    if isinstance(model, str):
        parser.exit(1, model + "\n")
    try:
        fixture = prepare(model, args.profiles, attempts=args.attempts)
    except PrepareError as exc:
        parser.exit(1, f"prepare failed: {exc}\n")
    args.output.write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {len(fixture['decisions'])} decisions and {len(fixture['explanations'])} explanations "
          f"to {args.output}; next: python -m scripts.export_demo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
