"""Environment configuration (BACKEND.md section 15). Secrets stay in backend/.env.

Invalid values stop startup with one clear ConfigError line instead of a traceback.
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

from app.ai.prompts import PROMPT_VERSION

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

THINKING_LEVELS = {"minimal", "low", "medium", "high"}
IOS_TIMEOUT_SECONDS = 8.0


class ConfigError(SystemExit):
    """Raised for bad environment values; exits with a readable message."""

    def __init__(self, message: str):
        super().__init__(f"Config error: {message} (check backend/.env)")


@dataclass(frozen=True)
class Settings:
    app_env: str = "hackathon"
    ai_enabled: bool = True
    ai_model: str = "gemini-3.5-flash-lite"
    gemini_api_key: str | None = None
    ai_thinking_level: str | None = "minimal"
    ai_prompt_version: str = PROMPT_VERSION  # owned by the prompt code, not .env
    ai_total_timeout_seconds: float = 4.0
    ai_min_explanation_seconds: float = 0.8
    plaid_enabled: bool = False
    max_body_bytes: int = 128 * 1024
    evaluations_per_minute: int = 120
    decision_store_size: int = 128
    decision_ttl_seconds: int = 7200

    @property
    def ai_available(self) -> bool:
        return self.ai_enabled and bool(self.gemini_api_key)


def _str(name: str, default: str | None) -> str | None:
    value = os.getenv(name)
    return default if value is None or not value.strip() else value.strip()


def _bool(name: str, default: bool) -> bool:
    value = _str(name, None)
    if value is None:
        return default
    if value.lower() in {"1", "true", "yes", "on"}:
        return True
    if value.lower() in {"0", "false", "no", "off"}:
        return False
    raise ConfigError(f"{name}={value!r} must be true or false")


def _number(name: str, default: float, low: float, high: float, cast=float):
    value = _str(name, None)
    if value is None:
        return default
    try:
        number = cast(value)
    except ValueError:
        raise ConfigError(f"{name}={value!r} must be a number") from None
    if not low <= number <= high:
        raise ConfigError(f"{name}={value!r} must be between {low} and {high}")
    return number


def load_settings() -> Settings:
    stale = _str("AI_PROMPT_VERSION", None)
    if stale is not None and stale != PROMPT_VERSION:
        logging.getLogger("adaptive_retirement").warning(
            "AI_PROMPT_VERSION=%s in .env is ignored; the prompt code is version %s", stale, PROMPT_VERSION)
    thinking = _str("AI_THINKING_LEVEL", "minimal").lower()  # empty -> default; "none" disables
    if thinking not in THINKING_LEVELS | {"none"}:
        raise ConfigError(f"AI_THINKING_LEVEL={thinking!r} must be one of {sorted(THINKING_LEVELS)} or none")
    settings = Settings(
        app_env=_str("APP_ENV", "hackathon"),
        ai_enabled=_bool("AI_ENABLED", True),
        ai_model=_str("AI_MODEL", "gemini-3.5-flash-lite"),
        gemini_api_key=_str("GEMINI_API_KEY", None),
        ai_thinking_level=None if thinking == "none" else thinking,
        # The whole AI pipeline must finish well inside the iOS request timeout.
        ai_total_timeout_seconds=_number("AI_TOTAL_TIMEOUT_SECONDS", 4.0, 0.5, IOS_TIMEOUT_SECONDS - 1),
        plaid_enabled=_bool("PLAID_ENABLED", False),
        decision_ttl_seconds=_number("SESSION_TTL_SECONDS", 7200, 60, 86400, cast=int),
    )
    if settings.plaid_enabled:
        raise ConfigError("PLAID_ENABLED=true is not supported yet; the Plaid adapter is a post-MVP stretch")
    return settings
