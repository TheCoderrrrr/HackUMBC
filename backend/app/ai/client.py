"""Structured-output model client. Gemini in production, fakes in tests.

Each call gets the time remaining in the shared deadline; there are no retries on
the interactive path (BACKEND.md section 9).
"""
from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from typing import Protocol, TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)

_executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="ai-call")
_GEMINI_MIN_TIMEOUT_MS = 10_000


class AITimeout(Exception):
    """The shared AI deadline ran out."""


class StructuredModel(Protocol):
    model_id: str

    def generate(self, system: str, prompt: str, schema: type[T], timeout_s: float) -> tuple[T, str | None]:
        """Return the parsed output and the model version that actually served it (if known)."""
        ...


class GeminiModel:
    def __init__(self, api_key: str, model_id: str, thinking_level: str | None = None):
        from google import genai

        self.model_id = model_id
        self._thinking_level = thinking_level
        self._client = genai.Client(api_key=api_key)

    def generate(self, system: str, prompt: str, schema: type[T], timeout_s: float) -> tuple[T, str | None]:
        if timeout_s <= 0.05:
            raise AITimeout()
        deadline = time.monotonic() + timeout_s
        future = _executor.submit(self._call, system, prompt, schema, deadline)
        try:
            return future.result(timeout=timeout_s)
        except FutureTimeout as exc:
            future.cancel()  # drops the call if it never started
            raise AITimeout() from exc

    def _call(self, system: str, prompt: str, schema: type[T], deadline: float) -> tuple[T, str | None]:
        from google.genai import types

        remaining = deadline - time.monotonic()
        if remaining <= 0.05:  # waited in the queue past the deadline: don't call the provider
            raise AITimeout()
        config = types.GenerateContentConfig(
            system_instruction=system,
            temperature=0.2,
            response_mime_type="application/json",
            response_schema=schema,
            http_options=types.HttpOptions(
                # Gemini rejects server deadlines under 10s (400 INVALID_ARGUMENT). Our real
                # deadline is enforced by future.result(timeout=...) in generate().
                timeout=max(_GEMINI_MIN_TIMEOUT_MS, int(remaining * 1000)),
                retry_options=types.HttpRetryOptions(attempts=1),
            ),
        )
        if self._thinking_level:
            config.thinking_config = types.ThinkingConfig(thinking_level=self._thinking_level)
        response = self._client.models.generate_content(model=self.model_id, contents=prompt, config=config)
        if not response.text:
            raise ValueError("empty model response")
        return schema.model_validate_json(response.text), getattr(response, "model_version", None)
