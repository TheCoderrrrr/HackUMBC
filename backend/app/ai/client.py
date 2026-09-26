"""Structured-output model clients: OpenAI and Gemini in production, fakes in tests.

Each call gets the time remaining in the shared deadline; there are no retries on
the interactive path (BACKEND.md section 9). Both providers share the deadline,
cancellation and rate-limit handling in `_DeadlineModel`; they differ only in `_call`.
"""
from __future__ import annotations

import re
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from typing import Protocol, TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)

_executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="ai-call")
_GEMINI_MIN_TIMEOUT_MS = 10_000
REASONING_EFFORTS = {"none", "minimal", "low", "medium", "high"}


class AITimeout(Exception):
    """The shared AI deadline ran out."""


class AIRateLimited(Exception):
    """The provider refused the call for quota reasons (HTTP 429)."""

    def __init__(self, retry_after_s: float | None = None):
        super().__init__("rate limited")
        self.retry_after_s = retry_after_s


_RETRY_IN = re.compile(r"(?:retry|try again) in ([0-9.]+)\s*(ms|s)", re.IGNORECASE)


def _retry_after(message: str) -> float | None:
    match = _RETRY_IN.search(message or "")
    if not match:
        return None
    value = float(match.group(1))
    return value / 1000 if match.group(2).lower() == "ms" else value


class StructuredModel(Protocol):
    model_id: str

    def generate(self, system: str, prompt: str, schema: type[T], timeout_s: float) -> tuple[T, str | None]:
        """Return the parsed output and the model version that actually served it (if known)."""
        ...


class _DeadlineModel:
    """Runs one provider call on a worker thread and enforces the caller's deadline."""

    model_id: str

    def generate(self, system: str, prompt: str, schema: type[T], timeout_s: float) -> tuple[T, str | None]:
        if timeout_s <= 0.05:
            raise AITimeout()
        deadline = time.monotonic() + timeout_s
        future = _executor.submit(self._guarded_call, system, prompt, schema, deadline)
        try:
            return future.result(timeout=timeout_s)
        except FutureTimeout as exc:
            future.cancel()  # drops the call if it never started
            raise AITimeout() from exc
        except (AITimeout, AIRateLimited):
            raise
        except Exception as exc:
            retry = self._rate_limit_retry(exc)
            if retry is not False:
                raise AIRateLimited(retry) from exc
            raise

    def _guarded_call(self, system: str, prompt: str, schema: type[T], deadline: float) -> tuple[T, str | None]:
        remaining = deadline - time.monotonic()
        if remaining <= 0.05:  # waited in the queue past the deadline: don't call the provider
            raise AITimeout()
        return self._call(system, prompt, schema, remaining)

    def _call(self, system: str, prompt: str, schema: type[T], remaining_s: float) -> tuple[T, str | None]:
        raise NotImplementedError

    def _rate_limit_retry(self, exc: Exception) -> float | None | bool:
        """Seconds to wait if `exc` is a rate limit (None if unknown), or False if it is not one."""
        if getattr(exc, "code", None) == 429 or getattr(exc, "status_code", None) == 429:
            return _retry_after(str(exc))
        return False


class OpenAIModel(_DeadlineModel):
    """OpenAI Responses API with Structured Outputs (strict JSON schema from the Pydantic model)."""

    def __init__(self, api_key: str, model_id: str, reasoning_effort: str | None = None):
        from openai import OpenAI

        self.model_id = model_id
        self._effort = reasoning_effort
        self._client = OpenAI(api_key=api_key, max_retries=0)  # no retries on the interactive path

    def _call(self, system: str, prompt: str, schema: type[T], remaining_s: float) -> tuple[T, str | None]:
        import openai

        kwargs = {"reasoning": {"effort": self._effort}} if self._effort else {}
        try:
            response = self._client.responses.parse(
                model=self.model_id, instructions=system, input=prompt, text_format=schema,
                timeout=remaining_s, **kwargs,
            )
        except openai.APITimeoutError as exc:
            raise AITimeout() from exc
        parsed = response.output_parsed
        if parsed is None:  # refusal or incomplete output
            raise ValueError("model returned no structured output")
        return parsed, getattr(response, "model", None)

    def _rate_limit_retry(self, exc: Exception) -> float | None | bool:
        import openai

        if not isinstance(exc, openai.RateLimitError):
            return False
        headers = getattr(getattr(exc, "response", None), "headers", None) or {}
        for name, scale in (("retry-after-ms", 1000.0), ("retry-after", 1.0)):
            value = headers.get(name)
            if value:
                try:
                    return float(value) / scale
                except ValueError:
                    pass
        return _retry_after(str(exc))


class GeminiModel(_DeadlineModel):
    def __init__(self, api_key: str, model_id: str, thinking_level: str | None = None):
        from google import genai

        self.model_id = model_id
        self._thinking_level = thinking_level
        self._client = genai.Client(api_key=api_key)

    def _call(self, system: str, prompt: str, schema: type[T], remaining_s: float) -> tuple[T, str | None]:
        from google.genai import types

        config = types.GenerateContentConfig(
            system_instruction=system,
            temperature=0.2,
            response_mime_type="application/json",
            response_schema=schema,
            # We only want structured JSON; also silences the SDK's AFC warning.
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            http_options=types.HttpOptions(
                # Gemini rejects server deadlines under 10s (400 INVALID_ARGUMENT). Our real
                # deadline is enforced by future.result(timeout=...) in generate().
                timeout=max(_GEMINI_MIN_TIMEOUT_MS, int(remaining_s * 1000)),
                retry_options=types.HttpRetryOptions(attempts=1),
            ),
        )
        if self._thinking_level:
            config.thinking_config = types.ThinkingConfig(thinking_level=self._thinking_level)
        response = self._client.models.generate_content(model=self.model_id, contents=prompt, config=config)
        if not response.text:
            raise ValueError("empty model response")
        return schema.model_validate_json(response.text), getattr(response, "model_version", None)


def build_model(settings) -> StructuredModel | None:
    """The client for settings.ai_provider, or None when AI is disabled or the key is missing."""
    if not settings.ai_available:
        return None
    if settings.ai_provider == "openai":
        return OpenAIModel(settings.openai_api_key, settings.ai_model, settings.ai_reasoning_effort)
    return GeminiModel(settings.gemini_api_key, settings.ai_model, settings.ai_thinking_level)
