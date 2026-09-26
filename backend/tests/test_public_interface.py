"""Developer A names that Developer C's scripts import (DEVELOPER_A_NEEDS.md item 3).

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
