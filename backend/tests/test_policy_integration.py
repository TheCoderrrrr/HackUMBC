"""Real B-policy integration checks; activate when Kevin's branch is merged."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from app.engine.evaluate import evaluate  # noqa: E402
from app.engine.canonical import profile_hash  # noqa: E402
from app.engine.simulation import run_simulation  # noqa: E402
from scripts.export_demo import export_bundle  # noqa: E402


@unittest.skipUnless(
    importlib.util.find_spec("app.engine.policy") is not None,
    "Developer B's policy module has not been merged",
)
class PolicyIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from app.engine.policy import validate_decision
        from app.engine.state import derive_state

        cls.validate_decision = staticmethod(validate_decision)
        cls.derive_state = staticmethod(derive_state)
        profiles = json.loads((BACKEND / "fixtures/profiles.json").read_text())
        cls.profiles = {profile["id"]: profile for profile in profiles}

    def test_live_evaluator_uses_real_policy_for_all_three_profiles(self):
        for profile_id, profile in self.profiles.items():
            with self.subTest(profile=profile_id):
                state = self.derive_state(profile)
                decision = self.validate_decision(profile, state, None)
                result = evaluate(profile, None, decision)
                if hasattr(result, "model_dump"):
                    result = result.model_dump(mode="json")
                self.assertTrue(result["projections"]["current"]["feasible"])
                self.assertTrue(result["projections"]["adaptive"]["feasible"])
                self.assertIsNone(result["projections"]["custom"])
                self.assertEqual(result["explanation"]["source"], "template")
                self.assertEqual(
                    len(result["projections"]["adaptive"]["points"]),
                    12 * (profile["retirement_age"] - profile["age"]) + 1,
                )

    def test_morgan_first_month_matches_real_allocator(self):
        from app.engine.policy import allocate_month
        from app.engine.assumptions import MODEL_ASSUMPTIONS

        profile = self.profiles["morgan"]
        state = self.derive_state(profile)
        decision = self.validate_decision(profile, state, None)
        direct = allocate_month(profile, state, decision)
        simulated = run_simulation(profile, "adaptive", None, MODEL_ASSUMPTIONS, decision)
        opening = simulated.opening_allocation
        self.assertEqual(opening.employee_contribution_cents, direct["employee_contribution_cents"])
        self.assertEqual(opening.employee_cash_cost_cents, direct["employee_cash_cost_cents"])
        self.assertEqual(opening.employer_match_cents, direct["employer_match_cents"])
        self.assertEqual(opening.debt_payments[0].extra_cents, 96_380)
        self.assertEqual(simulated.projection.points[1].debt_cents, 1_701_120)

    def test_reviewed_variant_exception_uses_same_simulator(self):
        profile = json.loads((BACKEND / "fixtures/morgan-cash-security-profile.json").read_text())
        state = self.derive_state(profile)
        priorities = ["starter_reserve", "high_apr_debt", "full_reserve"]
        proposal = {
            "ordered_priorities": priorities,
            "rationale": [{
                "priority": priority,
                "summary": "Grounded recommendation",
                "evidence_paths": ["financial_state.emergency_months"],
                "tradeoff": "Cash committed here cannot serve another priority.",
            } for priority in priorities],
        }
        decision = self.validate_decision(
            profile, state, proposal, model_id="integration-fixture",
        )
        self.assertEqual(decision["source"], "ai")
        result = evaluate(profile, None, decision)
        if hasattr(result, "model_dump"):
            result = result.model_dump(mode="json")
        self.assertEqual(result["decision_summary"]["ordered_priorities"], priorities)
        self.assertTrue(result["projections"]["adaptive"]["feasible"])

    def test_missing_match_is_blocked_not_zero_match(self):
        from copy import deepcopy

        profile = deepcopy(self.profiles["morgan"])
        profile["employer_match"] = {
            "status": "unknown", "fully_vested": False, "tiers": [],
        }
        state = self.derive_state(profile)
        decision = self.validate_decision(profile, state, None)
        result = evaluate(profile, None, decision)
        if hasattr(result, "model_dump"):
            result = result.model_dump(mode="json")
        self.assertFalse(result["projections"]["adaptive"]["feasible"])
        self.assertIn("MISSING_REQUIRED_INPUT", result["warnings"])

    def test_export_replays_real_policy_without_provider_calls(self):
        """All review marks and saved text here are test-only synthetic inputs."""
        from app.engine.assumptions import MODEL_ASSUMPTIONS
        from app.engine.policy import default_priorities

        variant = json.loads((BACKEND / "fixtures/morgan-cash-security-profile.json").read_text())
        profiles = [*self.profiles.values(), variant]

        def proposal_for(profile):
            order = (
                ["starter_reserve", "high_apr_debt", "full_reserve"]
                if profile["id"] == "morgan-cash-security"
                else list(default_priorities(profile["planning_preference"]))
            )
            return {"ordered_priorities": order, "rationale": [{
                "priority": item,
                "summary": "Grounded recommendation",
                "evidence_paths": ["financial_state.emergency_months"],
                "tradeoff": "Cash committed here cannot serve another priority.",
            } for item in order]}

        def replay(profile, state, record):
            decision = self.validate_decision(
                profile, state, record["proposal"],
                model_id=record["model_id"],
            )
            self.assertEqual(decision["source"], record["expected_source"])
            decision["decision_id"] = record["decision_id"]
            return decision

        decisions = {}
        fallback_cases = []
        explanations = {}
        for profile in profiles:
            profile_id = profile["id"]
            saved = {
                "profile_hash": profile_hash(profile),
                "reviewers": ["A", "B"],
                "proposal": proposal_for(profile),
                "model_id": "test-only-model", "expected_source": "ai",
                "decision_id": profile_id + "-stable-test-id",
            }
            decisions[profile_id] = saved
            fallback_cases.append({
                "profile_id": profile_id,
                "profile_hash": profile_hash(profile),
                "reviewers": ["A", "B"],
                "proposal": None, "model_id": None,
                "expected_source": "rules_fallback",
                "decision_id": profile_id + "-fallback-test-id",
            })
            decision = replay(profile, self.derive_state(profile), saved)
            opening = run_simulation(
                profile, "adaptive", None, MODEL_ASSUMPTIONS, decision,
            ).opening_allocation
            scenarios = [None] if profile_id == "morgan-cash-security" else [
                None,
                {"retirement_age": profile["retirement_age"] + 2,
                 "employee_contribution_rate": None},
                {"retirement_age": profile["retirement_age"],
                 "employee_contribution_rate": round(opening.employee_contribution_rate + .01, 12)},
            ]
            for scenario in scenarios:
                result = evaluate(
                    profile, scenario, decision,
                )
                result_data = result.model_dump(mode="json") if hasattr(result, "model_dump") else result
                explanations[result_data["input_hash"]] = {
                    "reviewers": ["A", "B"],
                    "explanation": {
                        "source": "ai", "state_summary": "Test-only saved summary",
                        "narrative": "Test-only saved explanation", "changes": [],
                    },
                }

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile_file = root / "profiles.json"
            profile_file.write_text(json.dumps(profiles[:3]))
            (root / "morgan-cash-security-profile.json").write_text(json.dumps(variant))
            decisions_file = root / "decisions.json"
            decisions_file.write_text(json.dumps({
                "decisions": decisions,
                "fallback_cases": fallback_cases,
                "explanations": explanations,
            }))
            output = root / "generated"

            def export():
                return export_bundle(
                    profile_file, decisions_file, output,
                    profile_model=dict, scenario_model=dict,
                    explanation_model=dict, evaluation_model=dict,
                    state_fn=self.derive_state,
                    decision_validator=replay,
                    explanation_validator=lambda profile, evaluation, explanation: None,
                    assumptions=MODEL_ASSUMPTIONS,
                )

            manifest = export()
            self.assertEqual(len(manifest["artifacts"]), 10)
            before = {file.name: file.read_bytes() for file in output.iterdir()}
            export()
            self.assertEqual(before, {file.name: file.read_bytes() for file in output.iterdir()})


if __name__ == "__main__":
    unittest.main()
