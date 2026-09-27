"""Developer A names that Developer C's scripts import (docs/ENGINE_HANDOFF.md).

Renaming or changing these breaks scripts/export_demo.py and scripts/prepare_decisions.py,
so this test fails first. Change them only after telling Eric.
"""
from __future__ import annotations

import inspect


def test_names_used_by_c_scripts_exist():
    from app.ai.client import AIRateLimited, GeminiModel  # noqa: F401
    from app.ai.pipeline import situation_flags, valid_prose  # noqa: F401
    from app.ai.prompts import (  # noqa: F401
        PROMPT_VERSION, SYSTEM, ExplanationOut, explanation_prompt, recommendation_prompt, recommendation_schema,
    )
    from app.config import load_settings
    from app.engine_port import evidence_paths  # noqa: F401
    from app.schemas import AIExplanation, FinancialProfile, Scenario  # noqa: F401

    assert load_settings().ai_prompt_version == PROMPT_VERSION


def test_signatures_used_by_c_scripts():
    from app.ai.client import AIRateLimited, GeminiModel
    from app.ai.pipeline import situation_flags, valid_prose
    from app.ai.prompts import explanation_prompt, recommendation_prompt, recommendation_schema

    assert list(inspect.signature(situation_flags).parameters) == ["profile", "state"]
    assert list(inspect.signature(valid_prose).parameters) == ["out"]
    assert list(inspect.signature(recommendation_prompt).parameters) == [
        "preference", "permitted_orders", "indicators", "evidence_keys"]
    assert list(inspect.signature(explanation_prompt).parameters) == ["facts"]
    assert list(inspect.signature(recommendation_schema).parameters) == ["evidence_keys"]
    assert list(inspect.signature(GeminiModel.__init__).parameters) == [
        "self", "api_key", "model_id", "thinking_level"]
    assert list(inspect.signature(GeminiModel.generate).parameters) == [
        "self", "system", "prompt", "schema", "timeout_s"]
    assert hasattr(AIRateLimited(3.0), "retry_after_s")


def test_names_c_relies_on_for_openai_and_saved_decisions():
    """README "Open Implementation Items", Neil item 4."""
    from app.ai.client import OpenAIModel, build_model
    from app.ai.pipeline import explanation_facts
    from app.engine_port import permitted_orders
    from app.schemas import Evaluation

    assert "decision_summary" in Evaluation.model_fields and "explanation" in Evaluation.model_fields
    assert list(inspect.signature(permitted_orders).parameters) == ["profile"]
    assert list(inspect.signature(explanation_facts).parameters) == [
        "profile", "state", "core", "decision", "changes", "initial"]
    assert inspect.signature(explanation_facts).parameters["initial"].kind is inspect.Parameter.KEYWORD_ONLY
    assert list(inspect.signature(OpenAIModel.__init__).parameters) == [
        "self", "api_key", "model_id", "reasoning_effort"]
    assert list(inspect.signature(OpenAIModel.generate).parameters) == [
        "self", "system", "prompt", "schema", "timeout_s"]
    assert list(inspect.signature(build_model).parameters) == ["settings"]
