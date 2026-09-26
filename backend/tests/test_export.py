"""Replay, hashing, and staged-publication tests without A/B provider code."""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.engine.canonical import canonical_json, input_hash, profile_hash  # noqa: E402
from scripts.export_demo import (  # noqa: E402
    ExportError, PROFILE_IDS, STANDARD_IDS, VARIANT_ID, export_bundle,
    validate_bundle,
)


ASSUMPTIONS = {"annual_equity_return": 0.06, "annual_cash_return": 0}


def profiles() -> list[dict]:
    result = []
    for profile_id in STANDARD_IDS:
        result.append({
            "id": profile_id, "name": profile_id.title(),
            "planning_preference": "balanced", "age": 35,
            "retirement_age": 67, "annual_gross_salary_cents": 8_400_000,
            "monthly_take_home_cents": 480_000,
            "monthly_living_expenses_cents": 360_000,
            "employee_contribution_rate": 0.08,
            "retirement_balance_cents": 3_500_000,
            "emergency_cash_cents": 360_000,
        })
    variant = deepcopy(result[1])
    variant["id"] = VARIANT_ID
    variant["planning_preference"] = "cash_security"
    result.append(variant)
    return result


def decisions(source_profiles: list[dict]) -> dict[str, dict]:
    result = {}
    for profile in source_profiles:
        profile_id = profile["id"]
        result[profile_id] = {
            "profile_hash": profile_hash(profile),
            "reviewers": ["A", "B"],
            "decision_id": profile_id + "-saved",
            "expected_source": "ai",
            "model_id": "fixture-model",
            "prompt_version": "1",
            "proposal": {
                "decision_id": profile_id + "-saved",
                "source": "ai", "model_id": "fixture-model",
                "prompt_version": "1",
                "ordered_priorities": [
                    "starter_reserve", "high_apr_debt", "full_reserve"
                ],
            },
        }
    return result


def scenarios(profile: dict) -> list[dict | None]:
    retirement_age = profile["retirement_age"]
    return [
        None,
        {"retirement_age": retirement_age + 2, "employee_contribution_rate": None},
        {"retirement_age": retirement_age, "employee_contribution_rate": 0.06},
    ]


def fixtures(source_profiles: list[dict]) -> dict:
    records = decisions(source_profiles)
    explanations = {}
    fallbacks = []
    for profile in source_profiles:
        options = [None] if profile["id"] == VARIANT_ID else scenarios(profile)
        decision = records[profile["id"]]["proposal"]
        fallbacks.append({
            "profile_id": profile["id"],
            "profile_hash": profile_hash(profile),
            "reviewers": ["A", "B"],
            "decision_id": profile["id"] + "-fallback",
            "expected_source": "rules_fallback",
            "model_id": None,
            "prompt_version": "1",
            "proposal": {
                **decision,
                "decision_id": profile["id"] + "-fallback",
                "source": "rules_fallback", "model_id": None,
                "ordered_priorities": (
                    ["starter_reserve", "full_reserve", "high_apr_debt"]
                    if profile["id"] == VARIANT_ID else decision["ordered_priorities"]
                ),
            },
        })
        for scenario in options:
            hash_value = input_hash(
                profile, scenario, ASSUMPTIONS, decision,
                schema_version="1", model_version="1.0.0", policy_version="1.0.0",
            )
            explanations[hash_value] = {
                "reviewers": ["A", "B"],
                "explanation": {
                    "state_summary": profile["id"],
                    "narrative": f"Reviewed for {hash_value[:8]}",
                    "source": "ai", "changes": [],
                },
            }
    return {"decisions": records, "explanations": explanations,
            "fallback_cases": fallbacks}


def fake_evaluate(profile, scenario, decision, *, allow_morgan_exception=False):
    return {
        "schema_version": "1", "model_version": "1.0.0", "policy_version": "1.0.0",
        "profile_id": profile["id"],
        "input_hash": input_hash(
            profile, scenario, ASSUMPTIONS, decision,
            schema_version="1", model_version="1.0.0", policy_version="1.0.0",
        ),
        "financial_state": {},
        "plan": {"actions": [{"id": "employee-contribution", "employee_contribution_rate": 0.05}]},
        "assumptions": ASSUMPTIONS,
        "projections": {"current": {}, "adaptive": {}, "custom": None},
        "decision_summary": decision,
        "explanation": {
            "state_summary": "Template", "narrative": "Template",
            "source": "template", "changes": [],
        },
        "warnings": [],
    }


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source_profiles = profiles()
        self.fixture_data = fixtures(self.source_profiles)
        self.profiles_path = self.root / "source-profiles.json"
        self.decisions_path = self.root / "source-decisions.json"
        self.output = self.root / "generated"
        self._save_sources()

    def _save_sources(self):
        self.profiles_path.write_text(
            json.dumps({"schema_version": "1", "profiles": self.source_profiles}),
            encoding="utf-8",
        )
        self.decisions_path.write_text(json.dumps(self.fixture_data), encoding="utf-8")

    def _export(self, decision_validator=None):
        return export_bundle(
            self.profiles_path, self.decisions_path, self.output,
            profile_model=dict, scenario_model=dict,
            explanation_model=dict, evaluation_model=dict,
            state_fn=lambda profile: {},
            decision_validator=decision_validator or (
                lambda profile, state, record: record["proposal"]
            ),
            explanation_validator=lambda profile, evaluation, explanation: None,
            assumptions=ASSUMPTIONS,
            evaluator=fake_evaluate,
            opening_rate_fn=lambda profile, assumptions, decision: 0.05,
        )

    def _bytes(self):
        return {p.name: p.read_bytes() for p in self.output.iterdir()}

    def test_ten_artifacts_and_repeat_export_are_identical(self):
        manifest = self._export()
        self.assertEqual(len(manifest["artifacts"]), 10)
        self.assertEqual(manifest["default_profile_ids"], list(STANDARD_IDS))
        self.assertEqual(len(self._bytes()), 12)
        before = self._bytes()
        self._export()
        self.assertEqual(before, self._bytes())
        self.assertEqual(
            validate_bundle(self.output, profile_model=dict, scenario_model=dict, evaluation_model=dict),
            manifest,
        )
        variant = next(item for item in manifest["artifacts"] if item["profile_id"] == VARIANT_ID)
        regular = next(item for item in manifest["artifacts"] if item["filename"] == "morgan-original.json")
        self.assertNotEqual(variant["profile_hash"], regular["profile_hash"])
        self.assertEqual(variant["base_profile_id"], "morgan")
        plus_one = json.loads((self.output / "morgan-contribution-plus-one.json").read_text())
        self.assertEqual(plus_one["scenario"]["employee_contribution_rate"], 0.06)

    def test_missing_or_stale_explanation_preserves_previous_bundle(self):
        self._export()
        before = self._bytes()
        self.fixture_data["explanations"].pop(next(iter(self.fixture_data["explanations"])))
        self._save_sources()
        with self.assertRaises(ExportError):
            self._export()
        self.assertEqual(before, self._bytes())

    def test_final_export_rejects_template_labeled_as_saved_ai(self):
        record = next(iter(self.fixture_data["explanations"].values()))
        record["explanation"]["source"] = "template"
        self._save_sources()
        with self.assertRaisesRegex(ExportError, "saved AI"):
            self._export()
        self.assertFalse(self.output.exists())

    def test_stale_decision_and_invalid_preset_fail(self):
        self.fixture_data["decisions"]["morgan"]["profile_hash"] = "stale"
        self._save_sources()
        with self.assertRaisesRegex(ExportError, "stale saved decision"):
            self._export()
        self.assertFalse(self.output.exists())
        self.fixture_data = fixtures(self.source_profiles)
        self._save_sources()
        with self.assertRaisesRegex(ExportError, "20% UI ceiling"):
            export_bundle(
                self.profiles_path, self.decisions_path, self.output,
                profile_model=dict, scenario_model=dict,
                explanation_model=dict, evaluation_model=dict,
                state_fn=lambda profile: {},
                decision_validator=lambda profile, state, record: record["proposal"],
                explanation_validator=lambda profile, evaluation, explanation: None,
                assumptions=ASSUMPTIONS, evaluator=fake_evaluate,
                opening_rate_fn=lambda profile, assumptions, decision: 0.20,
            )
        self.assertFalse(self.output.exists())

    def test_replay_rejects_changed_decision_provenance(self):
        def changed_model(profile, state, record):
            return {**record["proposal"], "model_id": "different-model"}

        with self.assertRaisesRegex(ExportError, "replayed model_id"):
            self._export(decision_validator=changed_model)
        self.assertFalse(self.output.exists())

    def test_outage_fixtures_are_required(self):
        self.fixture_data.pop("fallback_cases")
        self._save_sources()
        with self.assertRaisesRegex(ExportError, "outage fixtures"):
            self._export()
        self.assertFalse(self.output.exists())

    def test_publish_rename_failure_rolls_back(self):
        self._export()
        before = self._bytes()
        original_rename = Path.rename

        def fail_staged_rename(path, target):
            if ".staging-" in path.name and target == self.output:
                raise OSError("injected publish failure")
            return original_rename(path, target)

        with patch.object(Path, "rename", fail_staged_rename):
            with self.assertRaises(OSError):
                self._export()
        self.assertEqual(before, self._bytes())
        self.assertFalse(self.output.with_name("generated.backup").exists())

    def test_post_publish_validation_failure_restores_previous_bundle(self):
        self._export()
        before = self._bytes()
        from scripts import export_demo

        real_validate = export_demo.validate_bundle
        seen_output = 0

        def fail_new_output(directory, **kwargs):
            nonlocal seen_output
            if directory == self.output:
                seen_output += 1
                if seen_output == 2:
                    raise ExportError("injected post-publish validation failure")
            return real_validate(directory, **kwargs)

        with patch.object(export_demo, "validate_bundle", fail_new_output):
            with self.assertRaisesRegex(ExportError, "post-publish"):
                self._export()
        self.assertEqual(before, self._bytes())
        self.assertTrue(self.output.with_name("generated.failed").exists())

    def test_manifest_wrong_preset_link_is_rejected(self):
        self._export()
        path = self.output / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["artifacts"][0]["preset_id"] = "retire-plus-two"
        path.write_text(json.dumps(manifest))
        with self.assertRaises(ExportError):
            validate_bundle(self.output, profile_model=dict, scenario_model=dict, evaluation_model=dict)

    def test_interrupted_swap_recovers_on_next_run(self):
        self._export()
        before = self._bytes()
        self.output.rename(self.output.with_name("generated.backup"))
        self._export()
        self.assertEqual(before, self._bytes())
        self.assertFalse(self.output.with_name("generated.backup").exists())

    def test_two_valid_recovery_candidates_require_manual_resolution(self):
        self._export()
        before = self._bytes()
        backup = self.output.with_name("generated.backup")
        import shutil

        shutil.copytree(self.output, backup)
        with self.assertRaisesRegex(ExportError, "manual recovery required"):
            self._export()
        self.assertEqual(before, self._bytes())
        self.assertTrue(backup.exists())

    def test_canonical_hash_ignores_key_order_and_decision_id(self):
        profile = self.source_profiles[0]
        reordered = {key: profile[key] for key in reversed(list(profile))}
        self.assertEqual(profile_hash(profile), profile_hash(reordered))
        self.assertEqual(canonical_json({"rate": 0.050}), canonical_json({"rate": 0.05}))
        self.assertEqual(canonical_json({"rate": -0.0}), canonical_json({"rate": 0}))
        decision = self.fixture_data["decisions"]["jordan"]["proposal"]
        changed = {**decision, "decision_id": "new-id", "narrative": "new text"}
        kwargs = {"schema_version": "1", "model_version": "1.0.0", "policy_version": "1.0.0"}
        self.assertEqual(
            input_hash(profile, None, ASSUMPTIONS, decision, **kwargs),
            input_hash(profile, None, ASSUMPTIONS, changed, **kwargs),
        )
        self.assertNotEqual(
            input_hash(profile, None, ASSUMPTIONS, decision, **kwargs),
            input_hash({**profile, "emergency_cash_cents": 1}, None, ASSUMPTIONS, decision, **kwargs),
        )


if __name__ == "__main__":
    unittest.main()
