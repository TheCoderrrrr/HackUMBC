"""Deterministic shortlist of caller-supplied target-date fund facts.

This module does not discover funds or confirm IRA trade eligibility. Its scores
compare documented fit and fees; hypothetical return paths are illustrations,
not forecasts, and historical returns are never extrapolated into them.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator, model_validator


class HistoricalReturn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    period_years: int = Field(ge=1, le=30)
    annualized_return_rate: float = Field(ge=-1, le=2, allow_inf_nan=False)
    as_of_date: date
    source: str = Field(min_length=1)

    @field_validator("source")
    @classmethod
    def nonblank_source(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("historical return source cannot be blank")
        return value.strip()


class FundFacts(BaseModel):
    """``as_of_date`` dates holdings; fees may have an older document date.

    Missing core fields are allowed on input so incomplete rows can be excluded.
    """

    model_config = ConfigDict(extra="forbid")

    fund_id: str = Field(min_length=1)
    fund_type: Literal["target_date", "other"]
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    share_class_id: str | None = None
    name: str | None = None
    source: str | None = None
    source_url: HttpUrl | None = None
    prospectus_url: HttpUrl | None = None
    as_of_date: date | None = None
    catalog_status: Literal["listed", "unavailable"]
    expense_ratio: float | None = Field(default=None, ge=0, le=0.10, allow_inf_nan=False)
    expense_ratio_as_of_date: date | None = None
    expense_ratio_source: str | None = None
    equity_weight: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    bond_weight: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    other_weight: float | None = Field(default=None, ge=0, le=1, allow_inf_nan=False)
    target_year: int | None = Field(default=None, ge=1900, le=2200)
    historical_returns: list[HistoricalReturn] = Field(default_factory=list)

    @field_validator("fund_id")
    @classmethod
    def nonblank_id(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("fund ID cannot be blank")
        return value.strip()

    @field_validator("name", "source", "expense_ratio_source", "share_class_id")
    @classmethod
    def blank_is_missing(cls, value: str | None) -> str | None:
        return value.strip() or None if value is not None else None

    @model_validator(mode="after")
    def weights_balance(self) -> "FundFacts":
        if all(value is not None for value in (self.equity_weight, self.bond_weight, self.other_weight)):
            if abs(self.equity_weight + self.bond_weight + self.other_weight - 1) > 0.001:
                raise ValueError("equity, bond, and other weights must total 1")
        if len({item.period_years for item in self.historical_returns}) != len(self.historical_returns):
            raise ValueError("historical return periods must be unique")
        return self


class FundShortlistRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    account_type: Literal["401k", "ira"]
    as_of_date: date
    retirement_year: int = Field(ge=1900, le=2200)
    risk_tolerance: Literal["conservative", "moderate", "growth"]
    plan_menu_fund_ids: list[str] | None = None
    catalog: list[FundFacts]
    max_results: int = Field(default=3, ge=1, le=3)

    @field_validator("plan_menu_fund_ids")
    @classmethod
    def nonblank_plan_ids(cls, values: list[str] | None) -> list[str] | None:
        if values is None:
            return None
        if any(not value.strip() for value in values):
            raise ValueError("plan menu IDs cannot be blank")
        return [value.strip() for value in values]

    @model_validator(mode="after")
    def valid_horizon_and_ids(self) -> "FundShortlistRequest":
        if not self.as_of_date.year <= self.retirement_year <= self.as_of_date.year + 60:
            raise ValueError("retirement year must be within 60 years from as_of_date")
        if len({fund.fund_id for fund in self.catalog}) != len(self.catalog):
            raise ValueError("catalog fund IDs must be unique")
        if self.plan_menu_fund_ids is not None and len(set(self.plan_menu_fund_ids)) != len(self.plan_menu_fund_ids):
            raise ValueError("plan menu fund IDs must be unique")
        return self


class ScoreComponents(BaseModel):
    horizon_fit: float
    risk_fit: float
    fee_fit: float
    data_completeness: float


class HypotheticalScenario(BaseModel):
    label: Literal["low", "base", "high"]
    equity_assumption_rate: float
    bond_assumption_rate: float
    other_assumption_rate: float
    annual_net_return_rate: float
    years: int
    hypothetical_start_cents: int
    hypothetical_end_cents: int
    allocation_assumption: Literal["current_weights_held_constant"]


class FundRecommendation(BaseModel):
    fund_id: str
    fund_type: Literal["target_date"]
    currency: Literal["USD"]
    share_class_id: str
    name: str
    account_type: Literal["401k", "ira"]
    availability_label: Literal[
        "in_supplied_plan_menu", "research_candidate_plan_menu_unconfirmed",
        "discoverable_not_confirmed_purchasable",
    ]
    source: str
    source_url: HttpUrl
    prospectus_url: HttpUrl
    facts_as_of_date: date
    expense_ratio_source: str
    expense_ratio_as_of_date: date
    expense_ratio: float
    equity_weight: float
    bond_weight: float
    other_weight: float
    risk_band: int = Field(ge=1, le=5)
    risk_method: Literal["current_equity_weight_proxy_not_volatility"]
    risk_inputs: dict[str, float]
    target_year: int
    score: float
    score_components: ScoreComponents
    reason_codes: list[str]
    hypothetical_scenarios: list[HypotheticalScenario]
    historical_returns: list[HistoricalReturn]


class ExcludedFund(BaseModel):
    fund_id: str
    reason_code: Literal[
        "NOT_IN_PLAN_MENU", "UNAVAILABLE", "INCOMPLETE_FACTS", "STALE_FACTS",
        "NOT_TARGET_DATE", "NON_USD", "POOR_HORIZON_FIT", "POOR_RISK_FIT",
    ]


class FundShortlistResponse(BaseModel):
    account_type: Literal["401k", "ira"]
    as_of_date: date
    recommendations: list[FundRecommendation]
    excluded: list[ExcludedFund]
    plan_menu_status: Literal["unknown", "confirmed", "not_applicable"]
    score_weights: dict[str, float]
    assumption_set_version: str
    assumption_set_as_of_date: date
    hypothetical_disclosure: str


SCORE_WEIGHTS = {
    "horizon_fit": Decimal("0.40"),
    "risk_fit": Decimal("0.30"),
    "fee_fit": Decimal("0.20"),
    "data_completeness": Decimal("0.10"),
}
RISK_EQUITY_TARGETS = {
    "conservative": Decimal("0.40"),
    "moderate": Decimal("0.60"),
    "growth": Decimal("0.80"),
}
SCENARIO_ASSUMPTIONS = {
    "low": (Decimal("-0.02"), Decimal("0.00")),
    "base": (Decimal("0.06"), Decimal("0.03")),
    "high": (Decimal("0.10"), Decimal("0.05")),
}
OTHER_ASSET_RETURN_ASSUMPTION = Decimal("0.00")
ASSUMPTION_SET_VERSION = "prototype-1.0.0"
ASSUMPTION_SET_AS_OF_DATE = date(2026, 9, 26)
HYPOTHETICAL_START_CENTS = 1_000_000
MAX_HOLDINGS_AGE_DAYS = 90
MAX_FEE_AGE_DAYS = 548
MAX_HISTORY_AGE_DAYS = 548


def _decimal(value: float | int) -> Decimal:
    return Decimal(str(value))


def _clamp_unit(value: Decimal) -> Decimal:
    return max(Decimal(0), min(Decimal(1), value))


def _scenario(label: str, fund: FundFacts, years: int) -> HypotheticalScenario:
    equity, bond = SCENARIO_ASSUMPTIONS[label]
    annual_net = (_decimal(fund.equity_weight) * equity
                  + _decimal(fund.bond_weight) * bond
                  + _decimal(fund.other_weight) * OTHER_ASSET_RETURN_ASSUMPTION
                  - _decimal(fund.expense_ratio))
    terminal = int((Decimal(HYPOTHETICAL_START_CENTS) * (1 + annual_net) ** years)
                   .quantize(Decimal(1), rounding=ROUND_HALF_UP))
    return HypotheticalScenario(
        label=label, equity_assumption_rate=float(equity), bond_assumption_rate=float(bond),
        other_assumption_rate=float(OTHER_ASSET_RETURN_ASSUMPTION),
        annual_net_return_rate=float(annual_net), years=years,
        hypothetical_start_cents=HYPOTHETICAL_START_CENTS,
        hypothetical_end_cents=terminal,
        allocation_assumption="current_weights_held_constant",
    )


def shortlist_funds(request: FundShortlistRequest) -> FundShortlistResponse:
    """Rank at most three eligible catalog rows; never fetch or invent fund facts."""
    menu = None if request.plan_menu_fund_ids is None else set(request.plan_menu_fund_ids)
    years = request.retirement_year - request.as_of_date.year
    candidates: list[FundRecommendation] = []
    excluded: list[ExcludedFund] = []
    for fund in request.catalog:
        reason: str | None = None
        if fund.catalog_status == "unavailable":
            reason = "UNAVAILABLE"
        elif fund.fund_type != "target_date":
            reason = "NOT_TARGET_DATE"
        elif fund.currency != "USD":
            reason = "NON_USD"
        elif request.account_type == "401k" and menu is not None and fund.fund_id not in menu:
            reason = "NOT_IN_PLAN_MENU"
        elif any(value is None for value in (
            fund.share_class_id, fund.name, fund.source, fund.source_url,
            fund.prospectus_url, fund.as_of_date, fund.expense_ratio,
            fund.expense_ratio_source, fund.expense_ratio_as_of_date,
            fund.equity_weight, fund.bond_weight, fund.other_weight,
            fund.target_year,
        )):
            reason = "INCOMPLETE_FACTS"
        elif fund.as_of_date > request.as_of_date or (request.as_of_date - fund.as_of_date).days > MAX_HOLDINGS_AGE_DAYS:
            reason = "STALE_FACTS"
        elif fund.expense_ratio_as_of_date > request.as_of_date or (
            request.as_of_date - fund.expense_ratio_as_of_date
        ).days > MAX_FEE_AGE_DAYS:
            reason = "STALE_FACTS"
        if reason:
            excluded.append(ExcludedFund(fund_id=fund.fund_id, reason_code=reason))
            continue

        fresh_history = [item for item in fund.historical_returns
                         if item.as_of_date <= request.as_of_date
                         and (request.as_of_date - item.as_of_date).days <= MAX_HISTORY_AGE_DAYS]
        horizon_fit = _clamp_unit(1 - Decimal(abs(fund.target_year - request.retirement_year)) / 20)
        risk_fit = _clamp_unit(1 - abs(_decimal(fund.equity_weight) - RISK_EQUITY_TARGETS[request.risk_tolerance]) / Decimal("0.5"))
        if horizon_fit == 0 or risk_fit == 0:
            excluded.append(ExcludedFund(
                fund_id=fund.fund_id,
                reason_code="POOR_HORIZON_FIT" if horizon_fit == 0 else "POOR_RISK_FIT",
            ))
            continue
        fee_fit = _clamp_unit(1 - _decimal(fund.expense_ratio) / Decimal("0.01"))
        completeness = min(Decimal(1), Decimal("0.8") + Decimal("0.05") * len(fresh_history))
        components = {
            "horizon_fit": horizon_fit, "risk_fit": risk_fit,
            "fee_fit": fee_fit, "data_completeness": completeness,
        }
        score = sum(SCORE_WEIGHTS[key] * value for key, value in components.items())
        reason_codes = ["HORIZON_FIT", "RISK_FIT", "FEE_COMPARISON"]
        reason_codes.append("HISTORY_AVAILABLE" if fresh_history else "HISTORY_NOT_SUPPLIED")
        candidates.append(FundRecommendation(
            fund_id=fund.fund_id, fund_type="target_date", currency="USD",
            share_class_id=fund.share_class_id, name=fund.name,
            account_type=request.account_type,
            availability_label=(
                "discoverable_not_confirmed_purchasable" if request.account_type == "ira"
                else "research_candidate_plan_menu_unconfirmed" if menu is None
                else "in_supplied_plan_menu"
            ),
            source=fund.source, source_url=fund.source_url,
            prospectus_url=fund.prospectus_url, facts_as_of_date=fund.as_of_date,
            expense_ratio_source=fund.expense_ratio_source,
            expense_ratio_as_of_date=fund.expense_ratio_as_of_date,
            expense_ratio=fund.expense_ratio, equity_weight=fund.equity_weight,
            bond_weight=fund.bond_weight, other_weight=fund.other_weight,
            risk_band=max(1, min(5, int((_decimal(fund.equity_weight) * 5).to_integral_value(rounding=ROUND_CEILING)))),
            risk_method="current_equity_weight_proxy_not_volatility",
            risk_inputs={"equity_weight": fund.equity_weight,
                         "bond_weight": fund.bond_weight, "other_weight": fund.other_weight},
            target_year=fund.target_year,
            score=float(score),
            score_components=ScoreComponents(**{key: float(value) for key, value in components.items()}),
            reason_codes=reason_codes,
            hypothetical_scenarios=[_scenario(label, fund, years) for label in ("low", "base", "high")],
            historical_returns=fresh_history,
        ))
    candidates.sort(key=lambda item: (-item.score, item.expense_ratio, item.fund_id))
    return FundShortlistResponse(
        account_type=request.account_type, as_of_date=request.as_of_date,
        recommendations=candidates[:request.max_results], excluded=excluded,
        plan_menu_status=("not_applicable" if request.account_type == "ira"
                          else "unknown" if menu is None else "confirmed"),
        score_weights={key: float(value) for key, value in SCORE_WEIGHTS.items()},
        assumption_set_version=ASSUMPTION_SET_VERSION,
        assumption_set_as_of_date=ASSUMPTION_SET_AS_OF_DATE,
        hypothetical_disclosure=(
            "Low, base, and high paths are hypothetical illustrations from the disclosed "
            "equity and bond assumptions, a 0% other-asset assumption, and fund expense ratios. "
            "They hold today's equity/bond/other "
            "weights constant through the horizon; target-date funds can change their mix over time. "
            "The assumptions are prototype policy constants, not provider forecasts. These paths "
            "are not forecasts or guarantees. Historical returns are separate and do not predict future returns. "
            "A risk band is only a current equity-weight proxy, not measured volatility. "
            "IRA discovery and unknown 401(k) menus do not confirm purchase eligibility."
        ),
    )
