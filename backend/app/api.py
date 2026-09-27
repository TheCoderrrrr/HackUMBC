"""HTTP routes (BACKEND.md section 4). Routers contain no financial policy."""
from __future__ import annotations

from fastapi import APIRouter, Request

from app import engine_port as engine
from app.errors import ApiError
from app.limits import client_key
from app.schemas import SCHEMA_VERSION, DemoProfiles, ErrorEnvelope, EvaluateRequest, Evaluation, Health

router = APIRouter()

_ERRORS = {code: {"model": ErrorEnvelope} for code in (401, 413, 422, 429, 500, 503)}


@router.get("/health", response_model=Health)
def health(request: Request) -> Health:
    return Health(
        status="ok",
        schema_version=SCHEMA_VERSION,
        model_version=engine.MODEL_VERSION,
        policy_version=engine.POLICY_VERSION,
        plaid_enabled=request.app.state.settings.plaid_enabled,
        ai_available=request.app.state.settings.ai_available,
    )


@router.get("/v1/demo-profiles", response_model=DemoProfiles)
def demo_profiles() -> DemoProfiles:
    return DemoProfiles(schema_version=SCHEMA_VERSION, profiles=engine.load_demo_profiles())


@router.post("/v1/evaluate", response_model=Evaluation, responses=_ERRORS)
def evaluate(body: EvaluateRequest, request: Request) -> Evaluation:
    if not request.app.state.evaluate_limiter.allow(client_key(request)):
        raise ApiError(429, "RATE_LIMITED", "Too many evaluations. Try again in a minute.", retryable=True)
    if body.scenario and body.scenario.retirement_age <= body.profile.age:
        raise ApiError(422, "INVALID_REQUEST", "Scenario retirement age must be greater than current age.",
                       ["scenario.retirement_age"])
    return request.app.state.pipeline.run(body)


def _plaid_disabled() -> None:
    raise ApiError(503, "PLAID_DISABLED", "Plaid Sandbox is not enabled on this server.")


@router.post("/v1/plaid/link-token", responses=_ERRORS)
def plaid_link_token() -> None:
    _plaid_disabled()


@router.post("/v1/plaid/exchange", responses=_ERRORS)
def plaid_exchange() -> None:
    _plaid_disabled()


@router.post("/v1/plaid/import", responses=_ERRORS)
def plaid_import() -> None:
    _plaid_disabled()
