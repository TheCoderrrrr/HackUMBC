"""FastAPI app factory. Run: uvicorn app.main:app --host 127.0.0.1 --port 8000"""
from __future__ import annotations

import logging
import time

from fastapi import FastAPI, Request
from fastapi.middleware.gzip import GZipMiddleware

from app.ai.client import StructuredModel, build_model
from app.ai.pipeline import EvaluationPipeline
from app.analytics.router import router as history_router
from app.analytics.store import HistoryStore, build_history_store
from app.api import router
from app.config import Settings, load_settings
from app.decisions import DecisionStore
from app.errors import envelope, install_error_handlers
from app.fund_api import router as fund_router
from app.limits import RateLimiter

log = logging.getLogger("adaptive_retirement")
_FROM_ENV = object()


def create_app(settings: Settings | None = None, model: StructuredModel | None = None,
               history: HistoryStore | None = _FROM_ENV) -> FastAPI:
    settings = settings or load_settings()
    if model is None:
        model = build_model(settings)

    app = FastAPI(title="Adaptive Retirement Management (ARM) API", version="1.0.0")
    # Evaluations are 110–190 KB of monthly points and gzip ~85–90%; that headroom keeps
    # tunnel + cellular transfers well inside the app's 8 s timeout (REPORT A6).
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.state.settings = settings
    app.state.evaluate_limiter = RateLimiter(settings.evaluations_per_minute)
    app.state.pipeline = EvaluationPipeline(
        settings, model, DecisionStore(settings.decision_store_size, settings.decision_ttl_seconds)
    )
    # Optional Tiger Data scenario history; never needed by /v1/evaluate.
    app.state.history = build_history_store() if history is _FROM_ENV else history
    install_error_handlers(app)

    @app.middleware("http")
    async def guard_and_log(request: Request, call_next):
        length = request.headers.get("content-length")
        if length and length.isdigit() and int(length) > settings.max_body_bytes:
            return envelope(413, "PAYLOAD_TOO_LARGE", "Request body is larger than 128 KiB.")
        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception as exc:  # never let uvicorn print a traceback containing request data
            log.error("%s %s 500 %dms INTERNAL_ERROR %s", request.method, request.url.path,
                      int((time.perf_counter() - started) * 1000), type(exc).__name__)
            return envelope(500, "INTERNAL_ERROR", "Something went wrong. Please try again.", retryable=True)
        # Route, status and latency only: never request bodies or tokens.
        log.info("%s %s %d %dms", request.method, request.url.path, response.status_code,
                 int((time.perf_counter() - started) * 1000))
        return response

    app.include_router(router)
    app.include_router(fund_router)
    app.include_router(history_router)
    log.info("AI %s (provider=%s, model=%s)", "enabled" if model else "disabled: rules fallback",
             settings.ai_provider, settings.ai_model)
    return app


logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
app = create_app()
