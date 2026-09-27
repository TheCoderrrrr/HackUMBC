"""Scenario-history routes. Separate from /v1/evaluate, which never touches the database."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Query, Request, Response

from app.analytics import service
from app.analytics.models import Comparison, HistoryStatus, RunList, SaveRunRequest, SaveRunResponse
from app.analytics.store import HistoryStore, HistoryUnavailable
from app.errors import ApiError
from app.limits import client_key
from app.schemas import ErrorEnvelope

router = APIRouter(prefix="/v1/history", tags=["history"])

_ERRORS = {code: {"model": ErrorEnvelope} for code in (404, 409, 422, 429, 503)}
LIST_LIMIT = 20


def _store(request: Request) -> HistoryStore:
    store = getattr(request.app.state, "history", None)
    if store is None:
        raise ApiError(503, "HISTORY_DISABLED", "Scenario history is not configured on this server.")
    return store


def _unavailable() -> ApiError:
    return ApiError(503, "HISTORY_UNAVAILABLE", "Scenario history is unavailable right now. Try again.",
                    retryable=True)


def _run_id(value: str, field: str) -> str:
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise ApiError(422, "INVALID_REQUEST", "Run ID is not valid.", [field]) from None


@router.get("/status", response_model=HistoryStatus)
def status(request: Request) -> HistoryStatus:
    store = getattr(request.app.state, "history", None)
    return HistoryStatus(enabled=store is not None, available=bool(store and store.ping()))


@router.post("/runs", response_model=SaveRunResponse, status_code=201, responses=_ERRORS)
def save_run(body: SaveRunRequest, request: Request, response: Response) -> SaveRunResponse:
    store = _store(request)
    if not request.app.state.evaluate_limiter.allow(client_key(request)):
        raise ApiError(429, "RATE_LIMITED", "Too many requests. Try again in a minute.", retryable=True)
    record = service.build_run(body.profile_id, body.scenario, body.decision_summary, body.input_hash,
                               body.planning_preference)
    try:
        run, created = store.save(record)
    except HistoryUnavailable:
        raise _unavailable() from None
    if not created:
        response.status_code = 200
    return SaveRunResponse(run=run, created=created)


@router.get("/runs", response_model=RunList, responses=_ERRORS)
def list_runs(request: Request, profile_id: str = Query(min_length=1, max_length=64)) -> RunList:
    store = _store(request)
    try:
        return RunList(runs=store.list_runs(profile_id, LIST_LIMIT))
    except HistoryUnavailable:
        raise _unavailable() from None


@router.get("/compare", response_model=Comparison, responses=_ERRORS)
def compare(request: Request, base: str = Query(), other: str = Query()) -> Comparison:
    store = _store(request)
    base_id, other_id = _run_id(base, "base"), _run_id(other, "other")
    try:
        runs = store.get_runs([base_id, other_id])
        for run_id, field in ((base_id, "base"), (other_id, "other")):
            if run_id not in runs:
                raise ApiError(404, "RUN_NOT_FOUND", "That saved run doesn't exist.", [field])
        a, b = runs[base_id], runs[other_id]
        if base_id == other_id or a.profile_id != b.profile_id:
            return service.compare(a, b, [], [])  # raises the matching 422
        rows = store.yearly([(base_id, a.primary_strategy), (other_id, b.primary_strategy)])
    except HistoryUnavailable:
        raise _unavailable() from None
    return service.compare(a, b, rows[base_id], rows[other_id])
