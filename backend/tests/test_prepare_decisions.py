"""decisions.json preparation feeds the real exporter. TEST-ONLY synthetic model text."""
from __future__ import annotations

import json
import re
import tempfile
from pathlib import Path

import pytest

from app.ai.prompts import ExplanationOut, RecommendationOut
from scripts.export_demo import ExportError, export_bundle
from scripts.prepare_decisions import VARIANT_ORDER, PrepareError, prepare

PROFILES = Path(__file__).parents[1] / "fixtures" / "profiles.json"
ORDER = re.compile(r'\["[a-z_]+", "[a-z_]+", "[a-z_]+"\]')
RATIONALE = {
    "starter_reserve": ("Keep a small cushion before other goals.", ["emergency_cash_cents"]),
    "high_apr_debt": ("Costly card debt grows while it waits.", ["financial_state.high_interest_debt_cents"]),
    "full_reserve": ("A larger cushion follows the earlier goals.", ["financial_state.full_reserve_target_cents"]),
}


class ScriptedModel:
    """Chooses the last order the prompt permits, which is the variant's exception."""

    model_id = "test-only-model"

    def __init__(self, explanation="Your plan protects cash first. The target-date allocation is unchanged."):
        self.explanation = explanation
        self.calls = 0

    def generate(self, system, prompt, schema, timeout_s):
        self.calls += 1
        if schema is RecommendationOut:
            order = json.loads(ORDER.findall(prompt)[-1])
            return RecommendationOut.model_validate({"ordered_priorities": order, "rationale": [
                {"priority": p, "summary": RATIONALE[p][0], "evidence_paths": RATIONALE[p][1],
                 "tradeoff": "Cash placed here is not available elsewhere."} for p in order]}), "test-only-model-001"
        return ExplanationOut(state_summary="TEST ONLY summary without figures.", narrative=self.explanation), None


def reviewed(fixture):
    for record in [*fixture["decisions"].values(), *fixture["explanations"].values(), *fixture["fallback_cases"]]:
        record["reviewers"] = ["A", "B"]
    return fixture


def test_prepared_fixture_exports_a_valid_deterministic_bundle():
    fixture = prepare(ScriptedModel(), PROFILES, prompt_version="1")
    assert fixture["decisions"]["morgan-cash-security"]["proposal"]["ordered_priorities"] == VARIANT_ORDER
    assert fixture["decisions"]["morgan"]["model_id"] == "test-only-model-001"
    assert len(fixture["explanations"]) == 10 and len(fixture["fallback_cases"]) == 4
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        decisions = tmp / "decisions.json"
        decisions.write_text(json.dumps(reviewed(fixture)))
        manifest = export_bundle(PROFILES, decisions, tmp / "a")
        export_bundle(PROFILES, decisions, tmp / "b")
        assert len(manifest["artifacts"]) == 10
        for path in (tmp / "a").iterdir():
            assert path.read_bytes() == (tmp / "b" / path.name).read_bytes(), path.name


def test_unreviewed_fixture_is_refused():
    fixture = prepare(ScriptedModel(), PROFILES, prompt_version="1")
    with tempfile.TemporaryDirectory() as tmp:
        decisions = Path(tmp) / "decisions.json"
        decisions.write_text(json.dumps(fixture))
        with pytest.raises(ExportError, match="review marks"):
            export_bundle(PROFILES, decisions, Path(tmp) / "out")


def test_numeric_explanation_is_retried_then_rejected():
    model = ScriptedModel(explanation="Pay three hundred dollars a month.")
    with pytest.raises(PrepareError, match="no acceptable explanation after 2 attempts"):
        prepare(model, PROFILES, prompt_version="1", attempts=2)


def test_variant_must_choose_its_documented_exception():
    class DefaultOnly(ScriptedModel):
        def generate(self, system, prompt, schema, timeout_s):
            if schema is RecommendationOut:
                prompt = ORDER.sub(lambda m, first=ORDER.findall(prompt)[0]: first, prompt)
            return super().generate(system, prompt, schema, timeout_s)

    with pytest.raises(PrepareError, match="morgan-cash-security: no acceptable recommendation"):
        prepare(DefaultOnly(), PROFILES, prompt_version="1", attempts=2)
