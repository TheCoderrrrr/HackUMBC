"""Environment configuration (BACKEND.md section 15). Secrets stay in backend/.env."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")


def _bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    app_env: str = "hackathon"
    ai_enabled: bool = True
    ai_model: str = "gemini-3.5-flash-lite"
    gemini_api_key: str | None = None
    ai_thinking_level: str | None = "minimal"
    ai_prompt_version: str = "1"
    ai_total_timeout_seconds: float = 4.0
    plaid_enabled: bool = False
    max_body_bytes: int = 128 * 1024
    evaluations_per_minute: int = 120
    decision_store_size: int = 128
    decision_ttl_seconds: int = 7200

    @property
    def ai_available(self) -> bool:
        return self.ai_enabled and bool(self.gemini_api_key)


def load_settings() -> Settings:
    settings = Settings(
        app_env=os.getenv("APP_ENV", "hackathon"),
        ai_enabled=_bool("AI_ENABLED", True),
        ai_model=os.getenv("AI_MODEL", "gemini-3.5-flash-lite"),
        gemini_api_key=os.getenv("GEMINI_API_KEY") or None,
        ai_thinking_level=os.getenv("AI_THINKING_LEVEL", "minimal") or None,
        ai_prompt_version=os.getenv("AI_PROMPT_VERSION", "1"),
        ai_total_timeout_seconds=float(os.getenv("AI_TOTAL_TIMEOUT_SECONDS", "4")),
        plaid_enabled=_bool("PLAID_ENABLED", False),
        decision_ttl_seconds=int(os.getenv("SESSION_TTL_SECONDS", "7200")),
    )
    if settings.plaid_enabled:
        raise RuntimeError("PLAID_ENABLED=true is not supported yet; the Plaid adapter is a post-MVP stretch.")
    return settings
