"""Regenerate contracts/openapi.json and contracts/examples/ from the live FastAPI app.

Run from backend/:  python scripts/export_contracts.py
The iOS team decodes these files; rerun and commit them whenever app/schemas.py changes.
Examples use the rules fallback (no AI key, no network) so they are reproducible;
decision IDs are replaced with a fixed placeholder.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from fastapi.testclient import TestClient  # noqa: E402

from app import engine_port as engine  # noqa: E402
from app.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402

OUT = BACKEND.parent / "contracts"
EXAMPLES = OUT / "examples"
FIXED_DECISION_ID = "dec_example"


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print("wrote", path.relative_to(BACKEND.parent))


def stable(evaluation: dict) -> dict:
    evaluation["decision_summary"]["decision_id"] = FIXED_DECISION_ID
    return evaluation


def main() -> None:
    app = create_app(Settings(ai_enabled=False, gemini_api_key=None), model=None)
    client = TestClient(app)

    write(OUT / "openapi.json", app.openapi())
    write(EXAMPLES / "health.response.json", client.get("/health").json())
    profiles = client.get("/v1/demo-profiles").json()
    write(EXAMPLES / "demo-profiles.response.json", profiles)

    by_id = {p["id"]: p for p in profiles["profiles"]}
    for pid, profile in by_id.items():
        request = {"profile": profile, "scenario": None, "previous_decision_id": None}
        write(EXAMPLES / f"evaluate-{pid}.request.json", request)
        write(EXAMPLES / f"evaluate-{pid}.response.json", stable(client.post("/v1/evaluate", json=request).json()))

    morgan = by_id["morgan"]
    scenario = {"profile": morgan, "scenario": {"retirement_age": 69, "employee_contribution_rate": None}}
    write(EXAMPLES / "evaluate-morgan-scenario.request.json", scenario)
    write(EXAMPLES / "evaluate-morgan-scenario.response.json", stable(client.post("/v1/evaluate", json=scenario).json()))

    bad = json.loads(json.dumps(morgan))
    bad["debts"][0]["minimum_payment_cents"] = 0
    write(EXAMPLES / "error-invalid-profile.response.json", client.post("/v1/evaluate", json={"profile": bad}).json())
    infeasible = {"profile": morgan, "scenario": {"retirement_age": 67, "employee_contribution_rate": 0.5}}
    write(EXAMPLES / "error-infeasible-scenario.response.json", client.post("/v1/evaluate", json=infeasible).json())
    write(EXAMPLES / "error-plaid-disabled.response.json", client.post("/v1/plaid/link-token", json={}).json())
    print(f"{len(by_id)} profiles exported; engine model {engine.MODEL_VERSION}")


if __name__ == "__main__":
    main()
