"""Build a full, validated FinancialProfile from a short form of the user's own numbers.

The desktop app's "Your numbers" profile uses this. The form asks only for what a person knows
(age, pay, spending, savings, match, debts); this module fills in the rest, marks each entered
field `user_confirmed` in provenance, and returns an engine-computed preview so the form can
show real numbers (budget after essentials, emergency months, rate for the full match) while
the user types. Nothing here is stored: the profile lives in the user's browser, and scenario
history only accepts demo profiles, so personal numbers never reach the cloud database.
"""
from __future__ import annotations

import re
import secrets
from datetime import date
from typing import Literal

from fastapi import APIRouter, Request, Response
from pydantic import Field, ValidationError, model_validator

from app import engine_port as engine
from app.analytics.owner import owner_from
from app.analytics.router import _store, _unavailable
from app.analytics.store import HistoryUnavailable
from app.errors import ApiError
from app.limits import client_key
from app.schemas import Cents, ErrorEnvelope, FinancialProfile, FinancialState, PlanningPreference, Rate, Strict

router = APIRouter(prefix="/v1/profiles", tags=["profiles"])
_ERRORS = {code: {"model": ErrorEnvelope} for code in (401, 404, 422, 429, 503)}

MANUAL_PROFILE_ID = "me"
# 2026 employee elective-deferral limit (IRS 402(g)), the same value the demo fixtures use.
EMPLOYEE_LIMIT_CENTS = 2_450_000
DEFAULT_MARGINAL_TAX_RATE = 0.22


class MatchInput(Strict):
    """How the employer matches: "match" = `match_per_dollar` for each dollar up to `up_to_rate` of pay."""

    kind: Literal["match", "none", "unknown"]
    up_to_rate: Rate | None = Field(default=None, gt=0, le=1)
    match_per_dollar: float | None = Field(default=None, gt=0, le=2.0)

    @model_validator(mode="after")
    def _complete(self) -> MatchInput:
        if self.kind == "match" and (self.up_to_rate is None or self.match_per_dollar is None):
            raise ValueError("Enter how much your employer matches and up to what share of pay.")
        return self


class DebtInput(Strict):
    type: Literal["credit_card", "student_loan", "other"]
    balance_cents: Cents = Field(ge=0)
    apr: Rate = Field(ge=0, le=1)
    minimum_payment_cents: Cents = Field(ge=0)


class ProfileInput(Strict):
    name: str = Field(default="You", min_length=1, max_length=100)
    age: int = Field(ge=18, le=75)
    retirement_age: int = Field(le=80)
    annual_gross_salary_cents: Cents = Field(gt=0)
    monthly_take_home_cents: Cents = Field(ge=0)
    monthly_living_expenses_cents: Cents = Field(gt=0)
    employee_contribution_rate: Rate = Field(ge=0, le=1)
    retirement_balance_cents: Cents = Field(ge=0)
    emergency_cash_cents: Cents = Field(ge=0)
    match: MatchInput
    debts: list[DebtInput] = Field(default_factory=list, max_length=20)
    contribution_tax_treatment: Literal["traditional", "roth"] = "traditional"
    estimated_marginal_income_tax_rate: Rate = Field(default=DEFAULT_MARGINAL_TAX_RATE, ge=0, le=0.5)
    planning_preference: PlanningPreference = "balanced"


class ProfileBuild(Strict):
    profile: FinancialProfile
    preview: FinancialState
    blocking_issue: str | None


class StoredProfile(Strict):
    """The user's saved numbers: the form as entered, and the profile built from it."""

    form: ProfileInput
    profile: FinancialProfile


_ENTERED = (
    "name", "age", "retirement_age", "annual_gross_salary_cents", "monthly_take_home_cents",
    "monthly_living_expenses_cents", "employee_contribution_rate", "retirement_balance_cents",
    "emergency_cash_cents", "employer_match", "debts", "contribution_tax_treatment",
    "estimated_marginal_income_tax_rate", "planning_preference",
)
_DEFAULTED = ("schema_version", "id", "as_of_date", "currency", "source", "annual_employee_limit_cents")
# Profile field paths back to the form's field names, for error messages.
_FORM_PATH = {"employer_match": "match"}


def build_profile(body: ProfileInput, today: date | None = None, profile_id: str = MANUAL_PROFILE_ID) -> FinancialProfile:
    today = today or date.today()
    if body.match.kind == "match":
        match = {"status": "confirmed", "fully_vested": True, "tiers": [{
            "employee_rate_from": 0.0, "employee_rate_to": body.match.up_to_rate,
            "match_per_employee_dollar": body.match.match_per_dollar,
        }]}
    else:
        match = {"status": body.match.kind, "fully_vested": True, "tiers": []}
    stamp = today.isoformat()
    raw = {
        "schema_version": "1",
        "id": profile_id,
        "name": body.name,
        "as_of_date": stamp,
        "currency": "USD",
        "source": "manual",
        "age": body.age,
        "retirement_age": body.retirement_age,
        "annual_gross_salary_cents": body.annual_gross_salary_cents,
        "monthly_take_home_cents": body.monthly_take_home_cents,
        "monthly_living_expenses_cents": body.monthly_living_expenses_cents,
        "annual_employee_limit_cents": EMPLOYEE_LIMIT_CENTS,
        "employee_contribution_rate": body.employee_contribution_rate,
        "contribution_tax_treatment": body.contribution_tax_treatment,
        "estimated_marginal_income_tax_rate": body.estimated_marginal_income_tax_rate,
        "retirement_balance_cents": body.retirement_balance_cents,
        "emergency_cash_cents": body.emergency_cash_cents,
        "employer_match": match,
        "debts": [{"id": f"debt-{i + 1}", **d.model_dump()} for i, d in enumerate(body.debts)],
        "planning_preference": body.planning_preference,
        "provenance": {
            **{f: {"source": "user_confirmed", "as_of_date": stamp} for f in _ENTERED},
            **{f: {"source": "fixture", "as_of_date": stamp} for f in _DEFAULTED},
        },
    }
    try:
        return FinancialProfile.model_validate(raw)
    except ValidationError as exc:
        err = exc.errors()[0]
        path = ".".join(str(p) for p in err.get("loc", ()))
        head = path.split(".")[0]
        path = path.replace(head, _FORM_PATH.get(head, head), 1) if path else "profile"
        raise ApiError(422, "INVALID_PROFILE", err.get("msg", "Invalid value.").removeprefix("Value error, "), [path]) from None


def preview_state(profile: FinancialProfile) -> tuple[FinancialState, str | None]:
    """The engine's own financial state for the profile (raises ProfileValidationError → 422)."""
    state = engine.derive_state(profile)
    fields = FinancialState.model_fields
    return FinancialState.model_validate({k: v for k, v in state.items() if k in fields}), engine.blocking_issue(profile, state)


@router.post("/build", response_model=ProfileBuild, responses=_ERRORS)
def build(body: ProfileInput, request: Request) -> ProfileBuild:
    if not request.app.state.evaluate_limiter.allow(client_key(request)):
        raise ApiError(429, "RATE_LIMITED", "Too many requests. Try again in a minute.", retryable=True)
    profile = build_profile(body)
    preview, blocking = preview_state(profile)
    return ProfileBuild(profile=profile, preview=preview, blocking_issue=blocking)


# ---- people's own numbers, stored in Tiger Data under a hash of their anonymous key ----

MAX_PROFILES = 10
_ID = re.compile(r"^(me|u-[0-9a-f]{8})$")


def _limit(request: Request) -> None:
    if not request.app.state.evaluate_limiter.allow(client_key(request)):
        raise ApiError(429, "RATE_LIMITED", "Too many requests. Try again in a minute.", retryable=True)


def _profile_id(value: str) -> str:
    if not _ID.match(value):
        raise ApiError(422, "INVALID_REQUEST", "Profile ID is not valid.", ["profile_id"])
    return value


class StoredProfiles(Strict):
    profiles: list[StoredProfile]


@router.get("", response_model=StoredProfiles, responses=_ERRORS)
def list_mine(request: Request) -> StoredProfiles:
    """Every person saved under this key, oldest first."""
    owner = owner_from(request, required=True)
    store = _store(request)
    try:
        rows = store.list_profiles(owner)
    except HistoryUnavailable:
        raise _unavailable() from None
    return StoredProfiles(profiles=[StoredProfile(form=ProfileInput.model_validate(f), profile=FinancialProfile.model_validate(p))
                                    for f, p in rows])


@router.post("", response_model=ProfileBuild, status_code=201, responses=_ERRORS)
def create_mine(body: ProfileInput, request: Request) -> ProfileBuild:
    """Adds a person under this key (up to 10) with a new server-made ID."""
    _limit(request)
    owner = owner_from(request, required=True)
    store = _store(request)
    try:
        if len(store.list_profiles(owner)) >= MAX_PROFILES:
            raise ApiError(409, "PROFILE_LIMIT", f"You can save up to {MAX_PROFILES} people. Erase one to add another.")
        return _save(store, owner, f"u-{secrets.token_hex(4)}", body)
    except HistoryUnavailable:
        raise _unavailable() from None


@router.put("/{profile_id}", response_model=ProfileBuild, responses=_ERRORS)
def update_mine(profile_id: str, body: ProfileInput, request: Request) -> ProfileBuild:
    _limit(request)
    owner = owner_from(request, required=True)
    profile_id = _profile_id(profile_id)
    store = _store(request)
    try:
        if store.get_profile(owner, profile_id) is None:
            raise ApiError(404, "PROFILE_NOT_FOUND", "No saved numbers with that ID for this key.")
        return _save(store, owner, profile_id, body)
    except HistoryUnavailable:
        raise _unavailable() from None


@router.get("/{profile_id}", response_model=StoredProfile, responses=_ERRORS)
def load_mine(profile_id: str, request: Request) -> StoredProfile:
    owner = owner_from(request, required=True)
    profile_id = _profile_id(profile_id)
    store = _store(request)
    try:
        stored = store.get_profile(owner, profile_id)
    except HistoryUnavailable:
        raise _unavailable() from None
    if stored is None:
        raise ApiError(404, "PROFILE_NOT_FOUND", "No saved numbers with that ID for this key.")
    return StoredProfile(form=ProfileInput.model_validate(stored[0]), profile=FinancialProfile.model_validate(stored[1]))


@router.delete("/{profile_id}", status_code=204, responses=_ERRORS)
def erase_mine(profile_id: str, request: Request) -> Response:
    """Erases one person's numbers and every plan saved from them."""
    owner = owner_from(request, required=True)
    profile_id = _profile_id(profile_id)
    store = _store(request)
    try:
        if not store.delete_profile(owner, profile_id):
            raise ApiError(404, "PROFILE_NOT_FOUND", "No saved numbers with that ID for this key.")
    except HistoryUnavailable:
        raise _unavailable() from None
    return Response(status_code=204)


def _save(store, owner: str, profile_id: str, body: ProfileInput) -> ProfileBuild:
    profile = build_profile(body, profile_id=profile_id)
    preview, blocking = preview_state(profile)  # invalid inputs never get stored
    store.save_profile(owner, profile_id, body.model_dump(mode="json"), profile.model_dump(mode="json"))
    return ProfileBuild(profile=profile, preview=preview, blocking_issue=blocking)
