"""OpenAI client and provider configuration (README "Open Implementation Items", Neil 1-2)."""
from __future__ import annotations

import json

import httpx
import openai
import pytest

from app.ai.client import AIRateLimited, AITimeout, GeminiModel, OpenAIModel, build_model
from app.ai.prompts import ExplanationOut, RecommendationOut, recommendation_schema
from app.config import ConfigError, Settings, load_settings

REQ = httpx.Request("POST", "https://api.openai.com/v1/responses")


class FakeResponses:
    """Stands in for client.responses; records the call and returns or raises a scripted result."""

    def __init__(self, result):
        self.result, self.kwargs = result, None

    def parse(self, **kwargs):
        self.kwargs = kwargs
        if isinstance(self.result, BaseException):
            raise self.result
        return self.result


class Parsed:
    def __init__(self, parsed, model="gpt-6-luna-2026-09-01"):
        self.output_parsed, self.model = parsed, model


def model_with(result, effort="low"):
    m = OpenAIModel(api_key="test-key-not-used", model_id="gpt-6-luna", reasoning_effort=effort)
    m._client.responses = FakeResponses(result)
    return m


GOOD = ExplanationOut(state_summary="A steady plan.", narrative="Savings come first, then debt.")


# --- OpenAIModel -----------------------------------------------------------------------


def test_parse_success_returns_output_and_served_model():
    m = model_with(Parsed(GOOD))
    out, served = m.generate("system text", "prompt text", ExplanationOut, timeout_s=3)
    assert out == GOOD and served == "gpt-6-luna-2026-09-01"
    kw = m._client.responses.kwargs
    assert kw["model"] == "gpt-6-luna" and kw["instructions"] == "system text" and kw["input"] == "prompt text"
    assert kw["text_format"] is ExplanationOut
    assert kw["reasoning"] == {"effort": "low"}
    assert 0 < kw["timeout"] <= 3  # only the time left in the shared deadline


def test_reasoning_omitted_when_effort_not_set():
    m = model_with(Parsed(GOOD), effort=None)
    m.generate("s", "p", ExplanationOut, timeout_s=3)
    assert "reasoning" not in m._client.responses.kwargs


def test_client_never_retries():
    assert OpenAIModel(api_key="k", model_id="gpt-6-luna")._client.max_retries == 0


def test_timeout_maps_to_ai_timeout():
    m = model_with(openai.APITimeoutError(request=REQ))
    with pytest.raises(AITimeout):
        m.generate("s", "p", ExplanationOut, timeout_s=3)


@pytest.mark.parametrize("headers,expected", [
    ({"retry-after-ms": "1500"}, 1.5),
    ({"retry-after": "7"}, 7.0),
    ({}, None),
])
def test_429_maps_to_rate_limited_with_retry_after(headers, expected):
    res = httpx.Response(429, headers=headers, request=REQ)
    m = model_with(openai.RateLimitError("Rate limit reached", response=res, body=None))
    with pytest.raises(AIRateLimited) as info:
        m.generate("s", "p", ExplanationOut, timeout_s=3)
    assert info.value.retry_after_s == expected


def test_refusal_is_a_provider_error_not_a_crash():
    m = model_with(Parsed(None))
    with pytest.raises(ValueError):
        m.generate("s", "p", ExplanationOut, timeout_s=3)


def test_deadline_already_passed_skips_the_provider():
    m = model_with(Parsed(GOOD))
    with pytest.raises(AITimeout):
        m.generate("s", "p", ExplanationOut, timeout_s=0.01)
    assert m._client.responses.kwargs is None


def test_evidence_enum_survives_strict_schema_conversion():
    from openai.lib._pydantic import to_strict_json_schema
    schema = json.dumps(to_strict_json_schema(recommendation_schema(["debt_burden", "financial_state.highest_debt_apr"])))
    assert '"enum": ["debt_burden", "financial_state.highest_debt_apr"]' in schema
    assert '"additionalProperties": false' in schema
    to_strict_json_schema(RecommendationOut)
    to_strict_json_schema(ExplanationOut)


def test_pipeline_labels_openai_failures(morgan):
    from .conftest import make_client
    body = make_client(model_with(openai.APITimeoutError(request=REQ))).post("/v1/evaluate", json={"profile": morgan}).json()
    assert body["decision_summary"]["source"] == "rules_fallback"
    assert body["decision_summary"]["fallback_reason"] == "TIMEOUT"


# --- configuration ---------------------------------------------------------------------------


AI_ENV_VARS = (
    "AI_ENABLED", "AI_PROVIDER", "AI_MODEL", "OPENAI_API_KEY", "GEMINI_API_KEY",
    "AI_REASONING_EFFORT", "AI_THINKING_LEVEL", "AI_TOTAL_TIMEOUT_SECONDS", "AI_PROMPT_VERSION",
)


def settings_env(monkeypatch, **env):
    # Clear every AI variable so the developer's shell (and nothing else) can't leak in
    # (REPORT C7; `AI_ENABLED=false pytest` used to fail the availability test).
    for name in AI_ENV_VARS:
        monkeypatch.delenv(name, raising=False)
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    return load_settings()


def test_settings_ignore_the_real_env_file(monkeypatch):
    # REPORT C7: app.config no longer loads backend/.env at import, so settings reflect
    # only the process environment — a developer's .env or shell can't leak into tests.
    for name in AI_ENV_VARS:
        monkeypatch.delenv(name, raising=False)
    assert load_settings().ai_available is False


def test_default_provider_is_gemini_flash_lite(monkeypatch):
    # Team decision (REPORT C1): Gemini by default — both AI calls fit the 4 s budget.
    s = settings_env(monkeypatch)
    assert (s.ai_provider, s.ai_model, s.ai_thinking_level) == ("gemini", "gemini-3.5-flash-lite", "minimal")


def test_openai_provider_defaults_to_gpt_6_luna(monkeypatch):
    s = settings_env(monkeypatch, AI_PROVIDER="openai")
    assert (s.ai_model, s.ai_reasoning_effort) == ("gpt-6-luna", "low")


def test_ai_available_checks_the_selected_providers_key(monkeypatch):
    assert not settings_env(monkeypatch, AI_PROVIDER="openai", GEMINI_API_KEY="g").ai_available
    assert settings_env(monkeypatch, AI_PROVIDER="openai", OPENAI_API_KEY="o").ai_available
    assert not settings_env(monkeypatch, AI_PROVIDER="gemini", OPENAI_API_KEY="o").ai_available
    assert settings_env(monkeypatch, AI_PROVIDER="gemini", GEMINI_API_KEY="g").ai_available


@pytest.mark.parametrize("env", [
    {"AI_PROVIDER": "anthropic"},
    {"AI_PROVIDER": "openai", "AI_MODEL": "gemini-3.5-flash-lite"},
    {"AI_PROVIDER": "gemini", "AI_MODEL": "gpt-6-luna"},
    {"AI_REASONING_EFFORT": "extreme"},
])
def test_bad_provider_settings_stop_startup(monkeypatch, env):
    with pytest.raises(ConfigError):
        settings_env(monkeypatch, **env)


def test_build_model_picks_the_provider():
    assert build_model(Settings(ai_provider="openai", ai_model="gpt-6-luna", openai_api_key="o")).__class__ is OpenAIModel
    assert build_model(Settings(ai_provider="gemini", ai_model="gemini-3.5-flash-lite", gemini_api_key="g")).__class__ is GeminiModel
    assert build_model(Settings(ai_provider="openai", ai_model="gpt-6-luna")) is None  # no key -> rules fallback
    assert build_model(Settings(ai_enabled=False, ai_provider="openai", openai_api_key="o")) is None
