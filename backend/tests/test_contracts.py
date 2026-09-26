"""The committed contracts/ files must match the running app (rerun scripts/export_contracts.py)."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.config import Settings
from app.main import create_app
from app.schemas import DemoProfiles, ErrorEnvelope, EvaluateRequest, Evaluation, Health

CONTRACTS = Path(__file__).resolve().parents[2] / "contracts"
EXAMPLES = CONTRACTS / "examples"
STALE = "contracts/ is stale: run `python scripts/export_contracts.py` from backend/ and commit the result"


def load(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text(encoding="utf-8"))


def test_openapi_is_current():
    app = create_app(Settings(ai_enabled=False), model=None)
    assert json.loads((CONTRACTS / "openapi.json").read_text(encoding="utf-8")) == app.openapi(), STALE


@pytest.mark.parametrize("name,model", [
    ("health.response.json", Health),
    ("demo-profiles.response.json", DemoProfiles),
    *[(f"evaluate-{p}.request.json", EvaluateRequest) for p in ("jordan", "morgan", "casey", "morgan-scenario")],
    *[(f"evaluate-{p}.response.json", Evaluation) for p in ("jordan", "morgan", "casey", "morgan-scenario")],
    ("error-invalid-profile.response.json", ErrorEnvelope),
    ("error-infeasible-scenario.response.json", ErrorEnvelope),
    ("error-plaid-disabled.response.json", ErrorEnvelope),
])
def test_examples_match_the_contract(name, model):
    model.model_validate(load(name))


def test_examples_are_current(profiles):
    from fastapi.testclient import TestClient
    client = TestClient(create_app(Settings(ai_enabled=False), model=None))
    body = client.post("/v1/evaluate", json=load("evaluate-morgan.request.json")).json()
    body["decision_summary"]["decision_id"] = "dec_example"
    assert body == load("evaluate-morgan.response.json"), STALE
