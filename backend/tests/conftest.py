from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import engine_port as engine
from app.ai.client import AITimeout
from app.ai.prompts import ExplanationOut, RecommendationOut
from app.config import Settings
from app.main import create_app

GOOD_RATIONALE = {
    "starter_reserve": ("Keep a starter cushion on hand.", ["financial_state.emergency_months"], "Slower debt payoff."),
    "high_apr_debt": ("The card charges a high rate.", ["financial_state.highest_debt_apr"], "Less cash cushion for now."),
    "full_reserve": ("Build a larger cushion later.", ["financial_state.full_reserve_target_cents"], "Delays extra saving."),
}


def recommendation(order):
    return RecommendationOut.model_validate({
        "ordered_priorities": order,
        "rationale": [{"priority": p, "summary": GOOD_RATIONALE[p][0], "evidence_paths": GOOD_RATIONALE[p][1],
                       "tradeoff": GOOD_RATIONALE[p][2]} for p in order],
    })


GOOD_EXPLANATION = ExplanationOut(
    state_summary="You have a small cushion and an expensive card balance.",
    narrative="Extra cash goes to the card after your starter reserve. The illustrative target-date allocation is unchanged.",
)


class FakeModel:
    """Scripted structured model: each schema maps to a value, an exception, or a callable."""

    model_id = "fake-flash"

    def __init__(self, recommend=None, explain=GOOD_EXPLANATION, served_model=None):
        self.responses = {RecommendationOut: recommend, ExplanationOut: explain}
        self.served_model = served_model
        self.calls: list[type] = []
        self.timeouts: list[float] = []
        self.prompts: dict[type, str] = {}
        self.systems: list[str] = []

    def generate(self, system, prompt, schema, timeout_s):
        # The pipeline narrows RecommendationOut per request; record the base schema.
        schema = RecommendationOut if issubclass(schema, RecommendationOut) else schema
        self.calls.append(schema)
        self.timeouts.append(timeout_s)
        self.prompts[schema] = prompt
        self.systems.append(system)
        if timeout_s <= 0.05:
            raise AITimeout()
        value = self.responses[schema]
        if callable(value) and not isinstance(value, type):
            value = value(prompt)
        if isinstance(value, BaseException):
            raise value
        if value is None:
            order = engine.default_order(_preference_from(prompt))
            value = recommendation(order)
        return value, self.served_model


def _preference_from(prompt: str) -> str:
    for pref in ("balanced", "cash_security", "debt_reduction"):
        if f"'{pref}'" in prompt:
            return pref
    return "balanced"


def make_client(model=None, **overrides) -> TestClient:
    settings = Settings(**({"ai_enabled": True, "gemini_api_key": None} | overrides))
    return TestClient(create_app(settings, model=model))


@pytest.fixture(scope="session")
def profiles():
    """Canonical profiles from Developer B's fixtures (shared by engine and API tests)."""
    path = Path(__file__).parents[1] / "fixtures" / "profiles.json"
    return {profile["id"]: profile for profile in json.loads(path.read_text(encoding="utf-8"))}


@pytest.fixture
def morgan(profiles):
    return copy.deepcopy(profiles["morgan"])
