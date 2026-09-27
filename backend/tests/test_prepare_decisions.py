"""decisions.json preparation feeds the real exporter. TEST-ONLY synthetic model text."""
from __future__ import annotations

import json
import re
import tempfile
from pathlib import Path

import pytest

from app.ai.client import AIRateLimited
from app.ai.prompts import PROMPT_VERSION, ExplanationOut, RecommendationOut
from app.ai.client import OpenAIModel
from app.schemas import FinancialProfile
from scripts.export_demo import ExportError, export_bundle
from scripts.prepare_decisions import VARIANT_ORDER, PrepareError, load_profiles, model_from_settings, prepare

PROFILES = Path(__file__).parents[1] / "fixtures" / "profiles.json"
ORDER = re.compile(r'\["[a-z_]+", "[a-z_]+", "[a-z_]+"\]')
DEBT_FIRST = ["high_apr_debt", "starter_reserve", "full_reserve"]
RATIONALE = {
    "starter_reserve": ("Keep a small cushion before other goals.", ["emergency_cash_cents"]),
    "high_apr_debt": ("Costly card debt grows while it waits.", ["financial_state.high_interest_debt_cents"]),
    "full_reserve": ("A larger cushion follows the earlier goals.", ["financial_state.full_reserve_target_cents"]),
}


def recommendation(order):
    return RecommendationOut.model_validate({"ordered_priorities": order, "rationale": [
        {"priority": p, "summary": RATIONALE[p][0], "evidence_paths": RATIONALE[p][1],
         "tradeoff": "Cash placed here is not available elsewhere."} for p in order]})


class ScriptedModel:
    """Keeps the prompt's default order, except for a cash-security preference (the Morgan
    variant), where it picks starter -> debt -> full as the saved demonstration does."""

    model_id = "test-only-model"

    def __init__(self, explanation="Your plan protects cash first. The target-date allocation is unchanged.",
                 failures=()):
        self.explanation = explanation
        self.failures = list(failures)  # exceptions raised by the first calls, in order
        self.prompts: list[str] = []
        self.explain_prompts: list[str] = []

    def choose(self, prompt):
        return VARIANT_ORDER if "'cash_security'" in prompt else json.loads(ORDER.findall(prompt)[0])

    def generate(self, system, prompt, schema, timeout_s):
        if self.failures:
            raise self.failures.pop(0)
        if issubclass(schema, RecommendationOut):
            self.prompts.append(prompt)
            return recommendation(self.choose(prompt)), "test-only-model-001"
        self.explain_prompts.append(prompt)
        return ExplanationOut(state_summary="TEST ONLY summary without figures.", narrative=self.explanation), None


def write(tmp: Path, fixture) -> Path:
    path = tmp / "decisions.json"
    path.write_text(json.dumps(fixture))
    return path


def test_prepared_fixture_exports_a_valid_deterministic_bundle():
    fixture = prepare(ScriptedModel(), PROFILES)
    assert fixture["decisions"]["morgan-cash-security"]["proposal"]["ordered_priorities"] == VARIANT_ORDER
    assert fixture["decisions"]["morgan"]["model_id"] == "test-only-model-001"
    assert {r["prompt_version"] for r in [*fixture["decisions"].values(), *fixture["fallback_cases"]]} == {PROMPT_VERSION}
    assert len(fixture["explanations"]) == 10 and len(fixture["fallback_cases"]) == 4
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        decisions = write(tmp, fixture)  # straight from generation: no sign-off step
        manifest = export_bundle(PROFILES, decisions, tmp / "a")
        export_bundle(PROFILES, decisions, tmp / "b")
        assert len(manifest["artifacts"]) == 10
        for path in (tmp / "a").iterdir():
            assert path.read_bytes() == (tmp / "b" / path.name).read_bytes(), path.name


def test_prompts_match_the_live_api_and_carry_no_identifiers():
    model = ScriptedModel()
    prepare(model, PROFILES)
    assert len(model.prompts) == 4 and len(model.explain_prompts) == 10
    for prompt in model.prompts:  # A's permitted_orders: all three documented orders
        assert len(ORDER.findall(prompt)) == 3
    for prompt in [*model.prompts, *model.explain_prompts]:
        for identifier in ("Morgan", "Jordan", "Casey", "morgan-card", "jordan-student"):
            assert identifier not in prompt
    for prompt in model.explain_prompts:  # A's explanation_facts for an initial plan
        assert '"is_initial_plan": true' in prompt and '"changes": []' in prompt


def test_numeric_explanation_is_retried_then_rejected():
    model = ScriptedModel(explanation="Pay three hundred dollars a month.")
    with pytest.raises(PrepareError, match="no acceptable explanation after 2 attempts"):
        prepare(model, PROFILES, attempts=2)


def test_variant_must_choose_its_documented_exception():
    class DefaultOnly(ScriptedModel):
        def choose(self, prompt):
            return json.loads(ORDER.findall(prompt)[0])

    with pytest.raises(PrepareError, match="morgan-cash-security: no acceptable recommendation"):
        prepare(DefaultOnly(), PROFILES, attempts=2)


def test_standard_profile_must_keep_its_default_order():
    class DebtFirst(ScriptedModel):
        def choose(self, prompt):
            return DEBT_FIRST

    with pytest.raises(PrepareError, match="jordan: no acceptable recommendation.*saved item needs"):
        prepare(DebtFirst(), PROFILES, attempts=2)


@pytest.mark.parametrize("retry_after, expected_wait", [(7.0, 7.0), (None, 30.0), (500.0, 120.0)])
def test_rate_limit_waits_before_retrying(retry_after, expected_wait):
    waits: list[float] = []
    model = ScriptedModel(failures=[AIRateLimited(retry_after)])
    fixture = prepare(model, PROFILES, sleep=waits.append)
    assert waits == [expected_wait]
    assert len(fixture["decisions"]) == 4


def test_exported_morgan_shows_the_documented_card_payment():
    fixture = prepare(ScriptedModel(), PROFILES)
    assert not any("reviewers" in r for r in [*fixture["decisions"].values(), *fixture["explanations"].values()])
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        export_bundle(PROFILES, write(tmp, fixture), tmp / "generated")
        morgan = json.loads((tmp / "generated" / "morgan-original.json").read_text())
        card = next(r for r in morgan["evaluation"]["plan"]["reasons"] if r["facts"].get("debt_id") == "morgan-card")
        assert card["facts"]["extra_payment_cents"] == 96380


def test_numeric_saved_explanation_still_blocks_export():
    """Dropping human sign-off keeps the automatic prose check: no numbers reach the app."""
    fixture = prepare(ScriptedModel(), PROFILES)
    next(iter(fixture["explanations"].values()))["explanation"]["narrative"] = "Pay three hundred dollars."
    with tempfile.TemporaryDirectory() as tmp:
        with pytest.raises(ExportError, match="numbers"):
            export_bundle(PROFILES, write(Path(tmp), fixture), Path(tmp) / "generated")


def test_profiles_parse_with_the_shared_schema():
    assert all(isinstance(p, FinancialProfile) for p in load_profiles(PROFILES).values())


def test_model_comes_from_the_selected_provider(monkeypatch):
    monkeypatch.setenv("AI_ENABLED", "true")
    monkeypatch.setenv("AI_PROVIDER", "openai")
    monkeypatch.setenv("AI_MODEL", "gpt-6-luna")
    monkeypatch.setenv("OPENAI_API_KEY", "")
    assert model_from_settings() == "OPENAI_API_KEY is not set in backend/.env (AI_PROVIDER=openai)"

    monkeypatch.setenv("OPENAI_API_KEY", "sk-test-only")
    model = model_from_settings()
    assert isinstance(model, OpenAIModel) and model.model_id == "gpt-6-luna"

    monkeypatch.setenv("AI_PROVIDER", "gemini")
    monkeypatch.setenv("AI_MODEL", "gemini-3.5-flash-lite")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    assert model_from_settings() == "GEMINI_API_KEY is not set in backend/.env (AI_PROVIDER=gemini)"

    monkeypatch.setenv("AI_ENABLED", "false")
    assert "AI_ENABLED is false" in model_from_settings()
