"""Target-date fund shortlist routes. Separate from /v1/evaluate; never changes its contract."""
from __future__ import annotations

from datetime import date
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field, HttpUrl, ValidationError

from app.errors import ApiError
from app.fund_catalog import CatalogFund, CatalogStore, FundCatalog, ReportedCategory, effective_expense_ratio, to_fund_facts
from app.funds import FundShortlistRequest, FundShortlistResponse, shortlist_funds
from app.schemas import ErrorEnvelope

router = APIRouter(prefix="/v1/funds")

_ERRORS = {code: {"model": ErrorEnvelope} for code in (413, 422, 500, 503)}


class FundShortlistQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    account_type: Literal["401k", "ira"]
    retirement_year: int
    risk_tolerance: Literal["conservative", "moderate", "growth"]
    plan_menu_fund_ids: list[str] | None = Field(default=None, max_length=50)
    max_results: int = Field(default=3, ge=1, le=3)


class DocumentLink(BaseModel):
    title: str
    form: str
    filed_date: date
    url: HttpUrl


class FeeDetail(BaseModel):
    gross_expense_ratio: float
    acquired_fund_fees: float
    fee_waiver: float
    net_expense_ratio: float
    applied_expense_ratio: float
    waiver_active: bool
    waiver_ends: date | None
    waiver_terms: str
    as_of_date: date
    evidence_url: HttpUrl


class AllocationDetail(BaseModel):
    as_of_date: date
    reported_categories: list[ReportedCategory]
    mapping_note: str
    evidence_url: HttpUrl


class FundDetail(BaseModel):
    fund_id: str
    issuer: str
    registrant: str
    series_id: str
    share_class_id: str
    class_name: str
    ticker: str | None
    target_year: int
    fees: FeeDetail
    allocation: AllocationDetail
    glide_path: str
    prospectus: DocumentLink
    holdings_report: DocumentLink
    caveats: list[str]


class CatalogEntry(BaseModel):
    fund_id: str
    name: str
    issuer: str
    class_name: str
    ticker: str | None
    target_year: int


class CatalogSummary(BaseModel):
    catalog_version: str
    published_on: date
    reviewed_by: str
    review_note: str
    funds: list[CatalogEntry]


class FundShortlistEnvelope(BaseModel):
    catalog_version: str
    catalog_published_on: date
    catalog_reviewed_by: str
    unmatched_plan_menu_ids: list[str]
    shortlist: FundShortlistResponse
    details: dict[str, FundDetail]


def _today(request: Request) -> date:
    return getattr(request.app.state, "fund_today", date.today)()


def _catalog(request: Request) -> FundCatalog:
    store = getattr(request.app.state, "fund_catalog", None)
    if store is None:
        store = request.app.state.fund_catalog = CatalogStore()
    catalog = store.current()
    if catalog is None:
        raise ApiError(503, "FUND_CATALOG_UNAVAILABLE", "The reviewed fund catalog is not available right now.",
                       retryable=True)
    return catalog


def _link(catalog: FundCatalog, key: str) -> DocumentLink:
    doc = catalog.documents[key]
    return DocumentLink(title=doc.title, form=doc.form, filed_date=doc.filed_date, url=doc.url)


def _detail(fund: CatalogFund, catalog: FundCatalog, on: date) -> FundDetail:
    applied, waived = effective_expense_ratio(fund, on)
    fees, allocation = fund.fees, fund.allocation
    return FundDetail(
        fund_id=fund.fund_id, issuer=fund.issuer, registrant=fund.registrant, series_id=fund.series_id,
        share_class_id=fund.share_class_id, class_name=fund.class_name, ticker=fund.ticker,
        target_year=fund.target_year,
        fees=FeeDetail(
            gross_expense_ratio=fees.gross_expense_ratio, acquired_fund_fees=fees.acquired_fund_fees,
            fee_waiver=fees.fee_waiver, net_expense_ratio=fees.net_expense_ratio,
            applied_expense_ratio=applied, waiver_active=waived, waiver_ends=fees.waiver_ends,
            waiver_terms=fees.waiver_terms, as_of_date=fees.as_of_date,
            evidence_url=fees.evidence.url or catalog.documents[fees.evidence.document].url,
        ),
        allocation=AllocationDetail(
            as_of_date=allocation.as_of_date, reported_categories=allocation.reported_categories,
            mapping_note=allocation.mapping_note,
            evidence_url=allocation.evidence.url or catalog.documents[allocation.evidence.document].url,
        ),
        glide_path=fund.glide_path.summary,
        prospectus=_link(catalog, fund.prospectus_document),
        holdings_report=_link(catalog, allocation.evidence.document),
        caveats=fund.caveats,
    )


@router.get("/catalog", response_model=CatalogSummary, responses=_ERRORS)
def fund_catalog(request: Request) -> CatalogSummary:
    catalog = _catalog(request)
    return CatalogSummary(
        catalog_version=catalog.catalog_version, published_on=catalog.published_on,
        reviewed_by=catalog.reviewed_by, review_note=catalog.review_note,
        funds=[CatalogEntry(fund_id=f.fund_id, name=f.name, issuer=f.issuer, class_name=f.class_name,
                            ticker=f.ticker, target_year=f.target_year) for f in catalog.funds],
    )


@router.post("/shortlist", response_model=FundShortlistEnvelope, responses=_ERRORS)
def fund_shortlist(body: FundShortlistQuery, request: Request) -> FundShortlistEnvelope:
    today = _today(request)
    if not today.year <= body.retirement_year <= today.year + 60:
        raise ApiError(422, "INVALID_REQUEST", "Retirement year must be between this year and 60 years from now.",
                       ["retirement_year"])
    catalog = _catalog(request)
    menu = body.plan_menu_fund_ids if body.account_type == "401k" else None
    facts = [to_fund_facts(fund, catalog, today) for fund in catalog.funds]
    try:
        shortlist_request = FundShortlistRequest(
            account_type=body.account_type, as_of_date=today, retirement_year=body.retirement_year,
            risk_tolerance=body.risk_tolerance, plan_menu_fund_ids=menu, max_results=body.max_results,
            catalog=facts,
        )
    except ValidationError as exc:
        raise ApiError(422, "INVALID_REQUEST", exc.errors()[0]["msg"].removeprefix("Value error, "),
                       ["plan_menu_fund_ids"]) from None
    shortlist = shortlist_funds(shortlist_request)
    known = {fund.fund_id for fund in catalog.funds}
    return FundShortlistEnvelope(
        catalog_version=catalog.catalog_version, catalog_published_on=catalog.published_on,
        catalog_reviewed_by=catalog.reviewed_by,
        unmatched_plan_menu_ids=[fund_id for fund_id in menu or [] if fund_id.strip() not in known],
        shortlist=shortlist,
        details={item.fund_id: _detail(catalog.fund(item.fund_id), catalog, today)
                 for item in shortlist.recommendations},
    )
