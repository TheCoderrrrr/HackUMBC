"""Export ten reviewed offline evaluations through the live numerical engine.

Fixture format (owned jointly by A and B):
  decisions: {profile_id: {profile_hash, proposal, model_id, prompt_version,
                          decision_id, expected_source, reviewers: ["A", "B"]}}
  explanations: {input_hash: {explanation, reviewers: ["A", "B"]}}
  fallback_cases: [{profile_id, profile_hash, proposal, reviewers: ["A", "B"]}]
The two review marks document human sign-off; schema/evidence validation still
runs. No provider is contacted by this command.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from decimal import Decimal
import fcntl
from importlib import import_module
import json
from pathlib import Path
import shutil
import tempfile
from typing import Any, Callable, Iterator

from app.engine.canonical import canonical_json, input_hash, profile_hash
from app.engine.evaluate import evaluate
from app.engine.monthly import MissingHandoffError
from app.engine.simulation import decimal, get, run_simulation

STANDARD_IDS = ("jordan", "morgan", "casey")
VARIANT_ID = "morgan-cash-security"
PROFILE_IDS = (*STANDARD_IDS, VARIANT_ID)
PRESETS = ("original", "retire-plus-two", "contribution-plus-one")
EXPECTED_FILES = {
    "manifest.json", "profiles.json", "morgan-cash-security.json",
    *(f"{profile_id}-{preset}.json" for profile_id in STANDARD_IDS for preset in PRESETS),
}


class ExportError(RuntimeError):
    """The offline bundle cannot be safely produced or published."""


def _load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ExportError(f"cannot read valid JSON from {path}: {exc}") from exc


def _write(path: Path, value: Any) -> None:
    path.write_bytes(canonical_json(value) + b"\n")


def _model_dict(value: Any) -> dict[str, Any]:
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json", exclude_unset=False)
    if isinstance(value, dict):
        return value.copy()
    raise ExportError(f"expected validated model or dictionary, got {type(value).__name__}")


def _parse(model: Any, value: Any) -> Any:
    return model.model_validate(value) if hasattr(model, "model_validate") else model(**value)


def _require_review(record: Any, context: str) -> None:
    if not isinstance(record, dict) or set(record.get("reviewers", ())) != {"A", "B"}:
        raise ExportError(f"{context} requires Developer A and B review marks")


def _check_replayed_decision(record: dict[str, Any], decision: Any, profile_id: str) -> None:
    for field, expected in (
        ("decision_id", record.get("decision_id")),
        ("source", record.get("expected_source")),
        ("model_id", record.get("model_id")),
        ("prompt_version", record.get("prompt_version", "1")),
    ):
        if expected is None and field != "model_id":
            raise ExportError(f"{profile_id}: saved {field} is missing")
        if get(decision, field) != expected:
            raise ExportError(f"{profile_id}: replayed {field} does not match its saved record")
    proposal = record.get("proposal")
    if proposal is not None and list(get(decision, "ordered_priorities")) != proposal["ordered_priorities"]:
        raise ExportError(f"{profile_id}: replayed priority order does not match its saved record")


def _default_dependencies() -> dict[str, Any]:
    try:
        schemas = import_module("app.schemas")
        state = import_module("app.engine.state")
        policy = import_module("app.engine.policy")
        assumptions = import_module("app.engine.assumptions")
        def replay_decision(profile: Any, state_value: Any, record: dict[str, Any]) -> dict[str, Any]:
            profile_data = _model_dict(profile)
            is_variant = profile_data["id"] == VARIANT_ID
            decision = policy.validate_decision(
                profile_data, state_value, record["proposal"],
                model_id=record.get("model_id"),
                prompt_version=record.get("prompt_version", "1"),
                allow_morgan_exception=is_variant,
            )
            if decision["source"] != record["expected_source"]:
                raise ExportError(f"{profile_data['id']}: saved proposal fell back during validation")
            if not isinstance(record.get("decision_id"), str) or not record["decision_id"]:
                raise ExportError(f"{profile_data['id']}: saved decision ID is missing")
            decision["decision_id"] = record["decision_id"]
            return decision

        try:
            check_explanation = schemas.validate_saved_explanation
        except AttributeError as exc:
            raise MissingHandoffError(
                "Developer A must provide schemas.validate_saved_explanation "
                "to check saved claims against evaluation facts"
            ) from exc
        return {
            "profile_model": schemas.FinancialProfile,
            "scenario_model": schemas.Scenario,
            "explanation_model": schemas.AIExplanation,
            "evaluation_model": schemas.Evaluation,
            "state_fn": lambda profile: state.derive_state(_model_dict(profile)),
            "decision_validator": replay_decision,
            "explanation_validator": check_explanation,
            "assumptions": assumptions.MODEL_ASSUMPTIONS,
        }
    except (ImportError, AttributeError) as exc:
        raise MissingHandoffError(
            "Final export needs A's models and B's state, policy, and assumptions"
        ) from exc


def _default_opening_rate(profile: Any, assumptions: Any, decision: Any) -> float:
    run = run_simulation(profile, "adaptive", None, assumptions, decision)
    if not run.projection.feasible or run.opening_allocation is None:
        raise ExportError(f"{get(profile, 'id')}: opening Adaptive plan is infeasible")
    rate = run.opening_allocation.employee_contribution_rate
    if rate is None:
        raise ExportError("monthly allocator must expose its effective employee rate")
    return rate


def _artifact_specs(profiles: dict[str, Any], opening_rates: dict[str, float], scenario_model: Any) -> list[tuple[str, str, str, Any]]:
    specs: list[tuple[str, str, str, Any]] = []
    for profile_id in STANDARD_IDS:
        profile = profiles[profile_id]
        retirement_age = int(get(profile, "retirement_age"))
        plus_one = decimal(opening_rates[profile_id]) + Decimal("0.01")
        if plus_one > Decimal("0.20"):
            raise ExportError(f"{profile_id}: +1-point preset exceeds 20% UI ceiling")
        scenarios = (
            ("original", None),
            ("retire-plus-two", _parse(scenario_model, {
                "retirement_age": retirement_age + 2,
                "employee_contribution_rate": None,
            })),
            ("contribution-plus-one", _parse(scenario_model, {
                "retirement_age": retirement_age,
                "employee_contribution_rate": float(plus_one),
            })),
        )
        for preset_id, scenario in scenarios:
            specs.append((profile_id, preset_id, f"{profile_id}-{preset_id}.json", scenario))
    specs.append((VARIANT_ID, "original", "morgan-cash-security.json", None))
    return specs


def validate_bundle(
    directory: Path,
    *,
    profile_model: Any,
    scenario_model: Any,
    evaluation_model: Any,
) -> dict[str, Any]:
    """Reload the published shape and reject partial/mixed-version bundles."""
    if not directory.is_dir() or directory.is_symlink():
        raise ExportError(f"bundle directory is missing or is a symlink: {directory}")
    actual = {path.name for path in directory.iterdir()}
    if actual != EXPECTED_FILES or len(actual) != 12:
        raise ExportError(f"bundle files differ from expected set: {actual ^ EXPECTED_FILES}")
    manifest = _load(directory / "manifest.json")
    profiles_doc = _load(directory / "profiles.json")
    parsed_profiles = [_parse(profile_model, item) for item in profiles_doc["profiles"]]
    if profiles_doc.get("schema_version") != manifest.get("schema_version"):
        raise ExportError("profiles and manifest schema versions differ")
    profiles = {str(get(profile, "id")): profile for profile in parsed_profiles}
    if len(parsed_profiles) != 4 or set(profiles) != set(PROFILE_IDS):
        raise ExportError("profiles.json must contain three standard profiles and the Morgan variant")
    variant_fields = _model_dict(profiles[VARIANT_ID])
    morgan_fields = _model_dict(profiles["morgan"])
    for values in (variant_fields, morgan_fields):
        values.pop("id", None)
        values.pop("planning_preference", None)
        values.pop("provenance", None)
    if variant_fields != morgan_fields:
        raise ExportError("Morgan demonstration changes financial inputs")
    if manifest.get("default_profile_ids") != list(STANDARD_IDS):
        raise ExportError("manifest default customer IDs do not match the standard profiles")
    if manifest.get("profiles_file") != "profiles.json":
        raise ExportError("manifest profiles file mismatch")
    entries = manifest.get("artifacts", [])
    if len(entries) != 10 or len({item["filename"] for item in entries}) != 10:
        raise ExportError("manifest must map exactly ten unique evaluation artifacts")
    for entry in entries:
        filename = entry["filename"]
        profile_id = entry["profile_id"]
        if filename not in EXPECTED_FILES or profile_id not in profiles:
            raise ExportError(f"invalid manifest reference: {filename}")
        artifact = _load(directory / filename)
        profile = profiles[profile_id]
        if artifact["profile_id"] != profile_id or artifact["profile_hash"] != profile_hash(profile):
            raise ExportError(f"profile/hash mismatch in {filename}")
        scenario = (
            _parse(scenario_model, artifact["scenario"])
            if artifact["scenario"] is not None else None
        )
        evaluation = _parse(evaluation_model, artifact["evaluation"])
        eval_dict = _model_dict(evaluation)
        if eval_dict["profile_id"] != profile_id:
            raise ExportError(f"evaluation profile ID mismatch in {filename}")
        if eval_dict["decision_summary"]["source"] != "ai" or eval_dict["explanation"]["source"] != "ai":
            raise ExportError(f"final artifact lacks reviewed AI content in {filename}")
        versions = ("schema_version", "model_version", "policy_version")
        if any(
            artifact[key] != manifest[key] or eval_dict[key] != manifest[key]
            for key in versions
        ):
            raise ExportError(f"version mismatch in {filename}")
        expected_hash = input_hash(
            profile, scenario, eval_dict["assumptions"], eval_dict["decision_summary"],
            schema_version=manifest["schema_version"],
            model_version=manifest["model_version"],
            policy_version=manifest["policy_version"],
        )
        if eval_dict["input_hash"] != expected_hash or entry["input_hash"] != expected_hash:
            raise ExportError(f"input hash mismatch in {filename}")
        if entry["profile_hash"] != artifact["profile_hash"] or entry["filename"] != filename:
            raise ExportError(f"manifest hash or filename mismatch in {filename}")
        if entry["preset_id"] not in PRESETS:
            raise ExportError(f"unknown preset in {filename}")
        if profile_id == VARIANT_ID:
            if filename != "morgan-cash-security.json" or entry["preset_id"] != "original":
                raise ExportError("Morgan variant file or preset is invalid")
            if entry["kind"] != "demonstration" or entry["base_profile_id"] != "morgan":
                raise ExportError("Morgan variant manifest link is invalid")
            if scenario is not None:
                raise ExportError("Morgan demonstration must use the original scenario")
            if _model_dict(profiles[VARIANT_ID])["planning_preference"] != "cash_security":
                raise ExportError("Morgan demonstration preference is invalid")
            if eval_dict["decision_summary"]["ordered_priorities"] != [
                "starter_reserve", "high_apr_debt", "full_reserve"
            ]:
                raise ExportError("Morgan demonstration ordering is invalid")
        elif entry["kind"] != "standard" or entry["base_profile_id"] is not None:
            raise ExportError(f"standard preset is mislabeled: {filename}")
        else:
            expected_filename = f"{profile_id}-{entry['preset_id']}.json"
            if filename != expected_filename:
                raise ExportError(f"preset filename mismatch: {filename}")
            if entry["preset_id"] == "original" and scenario is not None:
                raise ExportError(f"original preset has a scenario: {filename}")
            if entry["preset_id"] == "retire-plus-two" and (
                scenario is None
                or get(scenario, "retirement_age") != get(profile, "retirement_age") + 2
                or get(scenario, "employee_contribution_rate") is not None
            ):
                raise ExportError(f"retire-plus-two scenario mismatch: {filename}")
            if entry["preset_id"] == "contribution-plus-one" and (
                scenario is None
                or get(scenario, "retirement_age") != get(profile, "retirement_age")
                or get(scenario, "employee_contribution_rate") is None
                or decimal(get(scenario, "employee_contribution_rate")) > Decimal("0.20")
            ):
                raise ExportError(f"contribution-plus-one scenario mismatch: {filename}")
            if entry["preset_id"] == "contribution-plus-one":
                actions = eval_dict["plan"]["actions"]
                employee = next((item for item in actions if item["id"] == "employee-contribution"), None)
                if employee is None or employee["employee_contribution_rate"] is None or (
                    decimal(get(scenario, "employee_contribution_rate"))
                    != decimal(employee["employee_contribution_rate"]) + Decimal("0.01")
                ):
                    raise ExportError(f"contribution-plus-one is not based on Adaptive: {filename}")
    return manifest


@contextmanager
def _export_lock(output: Path) -> Iterator[None]:
    lock_path = output.with_name(output.name + ".lock")
    with lock_path.open("a+b") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ExportError(f"another export is already using {output}") from exc
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def _recover(
    output: Path, *, profile_model: Any, scenario_model: Any, evaluation_model: Any,
) -> None:
    backup = output.with_name(output.name + ".backup")
    if not backup.exists():
        return
    if backup.is_symlink():
        raise ExportError(f"backup is a symlink; manual recovery required: {backup}")
    validate_bundle(
        backup, profile_model=profile_model, scenario_model=scenario_model,
        evaluation_model=evaluation_model,
    )
    if not output.exists():
        backup.rename(output)
        return
    validate_bundle(
        output, profile_model=profile_model, scenario_model=scenario_model,
        evaluation_model=evaluation_model,
    )
    raise ExportError(
        f"both the published bundle and backup are valid; "
        f"manual recovery required: {output}, {backup}"
    )


def _publish(
    staged: Path, output: Path, *, profile_model: Any, scenario_model: Any,
    evaluation_model: Any,
) -> None:
    backup = output.with_name(output.name + ".backup")
    if backup.exists():
        raise ExportError(f"unresolved backup: {backup}")
    had_output = output.exists()
    if had_output:
        if output.is_symlink():
            raise ExportError("refusing to replace a symlinked bundle")
        validate_bundle(
            output, profile_model=profile_model, scenario_model=scenario_model,
            evaluation_model=evaluation_model,
        )
        output.rename(backup)
    try:
        staged.rename(output)
        validate_bundle(
            output, profile_model=profile_model, scenario_model=scenario_model,
            evaluation_model=evaluation_model,
        )
    except Exception:
        if had_output and backup.exists() and not output.exists():
            backup.rename(output)
        elif had_output and backup.exists() and output.exists():
            failed = output.with_name(output.name + ".failed")
            if failed.exists():
                raise ExportError(
                    f"new bundle failed validation and {failed} already exists; "
                    "manual recovery required"
                )
            output.rename(failed)
            backup.rename(output)
        elif not had_output and output.exists():
            failed = output.with_name(output.name + ".failed")
            if failed.exists():
                raise ExportError(
                    f"new bundle failed validation and {failed} already exists; "
                    "manual recovery required"
                )
            output.rename(failed)
        raise
    if had_output:
        shutil.rmtree(backup)


def export_bundle(
    profiles_path: Path,
    decisions_path: Path,
    output: Path,
    *,
    profile_model: Any = None,
    scenario_model: Any = None,
    explanation_model: Any = None,
    evaluation_model: Any = None,
    state_fn: Callable[..., Any] | None = None,
    decision_validator: Callable[..., Any] | None = None,
    explanation_validator: Callable[..., Any] | None = None,
    assumptions: Any = None,
    evaluator: Callable[..., Any] = evaluate,
    opening_rate_fn: Callable[..., float] = _default_opening_rate,
) -> dict[str, Any]:
    if any(value is None for value in (
        profile_model, scenario_model, explanation_model, evaluation_model,
        state_fn, decision_validator, explanation_validator, assumptions,
    )):
        defaults = _default_dependencies()
        profile_model = profile_model or defaults["profile_model"]
        scenario_model = scenario_model or defaults["scenario_model"]
        explanation_model = explanation_model or defaults["explanation_model"]
        evaluation_model = evaluation_model or defaults["evaluation_model"]
        state_fn = state_fn or defaults["state_fn"]
        decision_validator = decision_validator or defaults["decision_validator"]
        explanation_validator = explanation_validator or defaults["explanation_validator"]
        assumptions = assumptions or defaults["assumptions"]

    output = output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    with _export_lock(output):
        _recover(
            output, profile_model=profile_model, scenario_model=scenario_model,
            evaluation_model=evaluation_model,
        )
        source_profiles = _load(profiles_path)
        if isinstance(source_profiles, list):
            variant_path = profiles_path.with_name("morgan-cash-security-profile.json")
            source_profiles = {"profiles": [*source_profiles, _load(variant_path)]}
        parsed = [_parse(profile_model, item) for item in source_profiles["profiles"]]
        profiles = {str(get(item, "id")): item for item in parsed}
        if len(parsed) != 4 or set(profiles) != set(PROFILE_IDS):
            raise ExportError("source profiles must include three standards and the Morgan variant")
        variant = profiles[VARIANT_ID]
        morgan = profiles["morgan"]
        if get(variant, "planning_preference") != "cash_security":
            raise ExportError("Morgan variant must select cash_security")
        variant_fields = _model_dict(variant).copy()
        morgan_fields = _model_dict(morgan).copy()
        for values in (variant_fields, morgan_fields):
            values.pop("id", None)
            values.pop("planning_preference", None)
            values.pop("provenance", None)
        if variant_fields != morgan_fields:
            raise ExportError("Morgan variant changes a financial input")

        fixtures = _load(decisions_path)
        decision_records = fixtures["decisions"]
        explanation_records = fixtures["explanations"]
        if set(decision_records) != set(PROFILE_IDS):
            raise ExportError("decision fixture must cover all four profiles")
        decisions: dict[str, Any] = {}
        opening_rates: dict[str, float] = {}
        for profile_id in PROFILE_IDS:
            profile = profiles[profile_id]
            record = decision_records[profile_id]
            _require_review(record, f"{profile_id} decision")
            if record["profile_hash"] != profile_hash(profile):
                raise ExportError(f"{profile_id}: stale saved decision")
            state = state_fn(profile)
            decisions[profile_id] = decision_validator(profile, state, record)
            _check_replayed_decision(record, decisions[profile_id], profile_id)
            if get(decisions[profile_id], "source") != "ai" or not get(decisions[profile_id], "model_id"):
                raise ExportError(f"{profile_id}: final artifacts require a reviewed saved AI decision")
            if profile_id in STANDARD_IDS:
                opening_rates[profile_id] = opening_rate_fn(
                    profile, assumptions, decisions[profile_id]
                )
        variant_order = list(get(decisions[VARIANT_ID], "ordered_priorities"))
        if variant_order != ["starter_reserve", "high_apr_debt", "full_reserve"]:
            raise ExportError("Morgan variant does not use its reviewed exception order")

        fallback_cases = fixtures.get("fallback_cases", [])
        if {record.get("profile_id") for record in fallback_cases} != set(PROFILE_IDS) or len(fallback_cases) != 4:
            raise ExportError("outage fixtures must cover all four profiles exactly once")
        for record in fallback_cases:
            profile_id = record["profile_id"]
            profile = profiles[profile_id]
            _require_review(record, f"{profile_id} outage fixture")
            if record["profile_hash"] != profile_hash(profile):
                raise ExportError(f"{profile_id}: stale outage fixture")
            fallback = decision_validator(profile, state_fn(profile), record)
            _check_replayed_decision(record, fallback, profile_id)
            if get(fallback, "source") != "rules_fallback" or get(fallback, "model_id") is not None:
                raise ExportError(f"{profile_id}: outage decision is mislabeled")
            fallback_evaluation = _model_dict(evaluator(
                profile, None, fallback,
                allow_morgan_exception=profile_id == VARIANT_ID,
            ))
            if fallback_evaluation["explanation"]["source"] != "template":
                raise ExportError(f"{profile_id}: outage explanation is not a template")

        staged = Path(tempfile.mkdtemp(prefix=output.name + ".staging-", dir=output.parent))
        published = False
        try:
            specs = _artifact_specs(profiles, opening_rates, scenario_model)
            manifest_entries: list[dict[str, Any]] = []
            versions: dict[str, str] | None = None
            used_explanations: set[str] = set()
            for profile_id, preset_id, filename, scenario in specs:
                profile = profiles[profile_id]
                try:
                    evaluation = evaluator(
                        profile, scenario, decisions[profile_id],
                        allow_morgan_exception=profile_id == VARIANT_ID,
                    )
                    data = _model_dict(evaluation)
                    if data["profile_id"] != profile_id:
                        raise ExportError("evaluator returned wrong profile ID")
                    current_versions = {key: data[key] for key in (
                        "schema_version", "model_version", "policy_version"
                    )}
                    if versions is None:
                        versions = current_versions
                    elif current_versions != versions:
                        raise ExportError("evaluation versions disagree")
                    hash_value = data["input_hash"]
                    expected = input_hash(
                        profile, scenario, data["assumptions"], data["decision_summary"],
                        **current_versions,
                    )
                    if hash_value != expected:
                        raise ExportError("evaluator input hash mismatch")
                    saved = explanation_records.get(hash_value)
                    _require_review(saved, f"{filename} explanation")
                    explanation = _parse(explanation_model, saved["explanation"])
                    if get(explanation, "source") != "ai":
                        raise ExportError("final artifact explanation must be reviewed saved AI")
                    explanation_validator(profile, data, explanation)
                    data["explanation"] = _model_dict(explanation)
                    data = _model_dict(_parse(evaluation_model, data))
                    if hash_value in used_explanations:
                        raise ExportError("two artifacts share an input hash")
                    used_explanations.add(hash_value)
                    artifact = {
                        "profile_id": profile_id,
                        "profile_hash": profile_hash(profile),
                        **current_versions,
                        "scenario": _model_dict(scenario) if scenario is not None else None,
                        "evaluation": data,
                    }
                    _write(staged / filename, artifact)
                    manifest_entries.append({
                        "profile_id": profile_id,
                        "preset_id": preset_id,
                        "filename": filename,
                        "profile_hash": artifact["profile_hash"],
                        "input_hash": hash_value,
                        "kind": "demonstration" if profile_id == VARIANT_ID else "standard",
                        "base_profile_id": "morgan" if profile_id == VARIANT_ID else None,
                    })
                except Exception as exc:
                    raise ExportError(f"{profile_id}/{preset_id}: {exc}") from exc
            if set(explanation_records) != used_explanations:
                raise ExportError("saved explanations include stale or unused input hashes")
            assert versions is not None
            _write(staged / "profiles.json", {
                "schema_version": versions["schema_version"],
                "profiles": [_model_dict(profiles[profile_id]) for profile_id in PROFILE_IDS],
            })
            manifest = {
                **versions,
                "profiles_file": "profiles.json",
                "default_profile_ids": list(STANDARD_IDS),
                "artifacts": manifest_entries,
            }
            _write(staged / "manifest.json", manifest)
            validate_bundle(
                staged, profile_model=profile_model, scenario_model=scenario_model,
                evaluation_model=evaluation_model,
            )
            _publish(
                staged, output, profile_model=profile_model,
                scenario_model=scenario_model, evaluation_model=evaluation_model,
            )
            published = True
            return manifest
        finally:
            if not published and staged.exists():
                shutil.rmtree(staged)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profiles", type=Path, default=Path("fixtures/profiles.json"))
    parser.add_argument("--decisions", type=Path, default=Path("fixtures/decisions.json"))
    parser.add_argument("--output", type=Path, default=Path("fixtures/generated"))
    args = parser.parse_args()
    try:
        manifest = export_bundle(args.profiles, args.decisions, args.output)
    except (ExportError, MissingHandoffError, ValueError, KeyError, TypeError) as exc:
        parser.exit(1, f"export failed: {exc}\n")
    print(f"exported {len(manifest['artifacts'])} artifacts to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
