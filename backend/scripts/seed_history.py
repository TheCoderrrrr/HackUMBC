"""Seed Tiger Data with synthetic scenario runs for the demo profiles.

    python -m scripts.seed_history            # from backend/, needs TIGER_DATABASE_URL

For each demo profile it saves two runs, "Plan as is" and "Retire 2 years later", computed
with the rules decision (no AI call). Saving is idempotent, so rerunning adds nothing new.
"""
from __future__ import annotations

import sys

from app import engine_port as engine
from app.ai.prompts import PROMPT_VERSION
from app.analytics import service
from app.analytics.store import HistoryUnavailable, build_history_store
from app.schemas import Scenario


def main() -> int:
    store = build_history_store()
    if store is None:
        print("TIGER_DATABASE_URL is not set in backend/.env")
        return 1
    try:
        for profile in engine.load_demo_profiles():
            state = engine.derive_state(profile)
            decision = engine.validate_decision(profile, state, None, prompt_version=PROMPT_VERSION,
                                                fallback_reason="AI_UNAVAILABLE")
            for scenario in (None, Scenario(retirement_age=min(profile.retirement_age + 2, 80))):
                core = engine.evaluate(profile, scenario, decision)
                record = service.build_run(profile.id, scenario, decision, core.input_hash)
                run, created = store.save(record)
                print(f"{'saved ' if created else 'exists'} {profile.id:7} {run.label:45} {run.run_id}")
    except HistoryUnavailable:
        print("Tiger Data is unreachable; check TIGER_DATABASE_URL and the service status.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
