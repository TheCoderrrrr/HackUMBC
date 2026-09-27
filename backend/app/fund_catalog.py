"""Reviewed target-date fund catalog: evidence records, FundFacts adapter, atomic publication.

Only hand-verified facts live here; the raw SEC staging database never does. Every datum
names the filing it came from, where in that filing, and its as-of date. Allocation weights
are derived deterministically from the issuer's own reported categories so the mapping
is reviewable, and a record that cannot be mapped cleanly is rejected rather than guessed.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import threading
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator

from app.funds import FundFacts, HistoricalReturn

log = logging.getLogger("adaptive_retirement")

DEFAULT_CATALOG_PATH = Path(__file__).resolve().parent / "data" / "fund_catalog.json"
CATALOG_SCHEMA_VERSION = "fund-catalog-1"
FEE_TOLERANCE = Decimal("0.00005")
MIN_CLASSIFIED_WEIGHT = Decimal("0.95")


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class SourceDocument(_Strict):
    issuer: str = Field(min_length=1)
    form: str = Field(min_length=1)
    accession: str = Field(pattern=r"^\d{10}-\d{2}-\d{6}$")
    filed_date: date
    effective_date: date | None = None
    period_date: date | None = None
    url: HttpUrl
    title: str = Field(min_length=1)


class Evidence(_Strict):
    document: str = Field(min_length=1)
    locator: str = Field(min_length=1)
    url: HttpUrl | None = None


class FeeFacts(_Strict):
    gross_expense_ratio: float = Field(ge=0, le=0.10)
    acquired_fund_fees: float = Field(ge=0, le=0.10)
    fee_waiver: float = Field(ge=0, le=0.10)
    net_expense_ratio: float = Field(ge=0, le=0.10)
    waiver_ends: date | None
    waiver_terms: str = Field(min_length=1)
    as_of_date: date
    evidence: Evidence

    @model_validator(mode="after")
    def arithmetic_matches_table(self) -> "FeeFacts":
        gross, waiver, net = (Decimal(str(v)) for v in (self.gross_expense_ratio, self.fee_waiver, self.net_expense_ratio))
        if abs(gross - waiver - net) > FEE_TOLERANCE:
            raise ValueError("gross expense ratio minus waiver must equal net expense ratio")
        if Decimal(str(self.acquired_fund_fees)) > gross:
            raise ValueError("acquired-fund fees cannot exceed the gross expense ratio")
        if waiver > 0 and self.waiver_ends is None:
            raise ValueError("a fee waiver needs its contractual end date")
        return self


class ReportedCategory(_Strict):
    label: str = Field(min_length=1)
    percent_of_net_assets: float = Field(ge=-100, le=200)
    bucket: Literal["equity", "bond", "other"]


class AllocationFacts(_Strict):
    """``other`` is the residual after equity and bond, so cash, money market funds,
    and securities-lending collateral net against other liabilities instead of double counting."""

    as_of_date: date
    reported_categories: list[ReportedCategory] = Field(min_length=1)
    mapping_note: str = Field(min_length=1)
    evidence: Evidence

    @model_validator(mode="after")
    def unambiguous(self) -> "AllocationFacts":
        labels = [item.label for item in self.reported_categories]
        if len(set(labels)) != len(labels):
            raise ValueError("reported allocation categories must be unique")
        equity, bond, _ = self.weights()
        if equity + bond > 1 + Decimal("0.0005"):
            raise ValueError("equity and bond weights exceed net assets")
        if equity + bond < MIN_CLASSIFIED_WEIGHT:
            raise ValueError("too little of the fund maps to equity or bonds; the record is ambiguous")
        return self

    def weights(self) -> tuple[Decimal, Decimal, Decimal]:
        def total(bucket: str) -> Decimal:
            return sum((Decimal(str(item.percent_of_net_assets)) for item in self.reported_categories
                        if item.bucket == bucket), Decimal(0)) / 100
        equity, bond = total("equity"), total("bond")
        if equity + bond > 1:  # rounding in the issuer's table; trim so the three weights total 1
            bond = 1 - equity
        return equity, bond, 1 - equity - bond


class GlidePath(_Strict):
    summary: str = Field(min_length=1)
    evidence: Evidence
    anchors: list[tuple[float, float]] | None = None

    @model_validator(mode="after")
    def valid_anchors(self) -> "GlidePath":
        if self.anchors is not None:
            if len(self.anchors) < 2 or any(y < 0 or not 0 <= w <= 1 for y, w in self.anchors):
                raise ValueError("glide-path anchors must be nonnegative years and equity fractions")
            if len({y for y, _ in self.anchors}) != len(self.anchors):
                raise ValueError("glide-path years must be unique")
        return self


class HistoricalReturnFacts(_Strict):
    period_years: int = Field(ge=1, le=30)
    annualized_return_rate: float = Field(ge=-1, le=2)
    as_of_date: date
    evidence: Evidence


class CatalogFund(_Strict):
    fund_id: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    name: str = Field(min_length=1)
    issuer: str = Field(min_length=1)
    registrant: str = Field(min_length=1)
    registrant_cik: str = Field(pattern=r"^\d{10}$")
    series_id: str = Field(pattern=r"^S\d{9}$")
    share_class_id: str = Field(pattern=r"^C\d{9}$")
    class_name: str = Field(min_length=1)
    ticker: str | None = Field(default=None, pattern=r"^[A-Z]{4,5}$")
    target_year: int = Field(ge=2000, le=2100)
    currency: Literal["USD"]
    catalog_status: Literal["listed", "unavailable"]
    identity_evidence: Evidence
    prospectus_document: str = Field(min_length=1)
    fees: FeeFacts
    allocation: AllocationFacts
    glide_path: GlidePath
    historical_returns: list[HistoricalReturnFacts] = Field(default_factory=list)
    caveats: list[str] = Field(default_factory=list)


class FundCatalog(_Strict):
    schema_version: Literal["fund-catalog-1"]
    catalog_version: str = Field(min_length=1)
    published_on: date
    reviewed_by: str = Field(min_length=1)
    review_note: str = Field(min_length=1)
    documents: dict[str, SourceDocument] = Field(min_length=1)
    funds: list[CatalogFund] = Field(min_length=1)

    @model_validator(mode="after")
    def consistent(self) -> "FundCatalog":
        ids = [fund.fund_id for fund in self.funds]
        if len(set(ids)) != len(ids):
            raise ValueError("catalog fund IDs must be unique")
        classes = [fund.share_class_id for fund in self.funds]
        if len(set(classes)) != len(classes):
            raise ValueError("each share class may appear only once")
        for fund in self.funds:
            evidence = [fund.identity_evidence, fund.fees.evidence, fund.allocation.evidence,
                        fund.glide_path.evidence, *(item.evidence for item in fund.historical_returns)]
            missing = {item.document for item in evidence} - self.documents.keys()
            if fund.prospectus_document not in self.documents:
                missing.add(fund.prospectus_document)
            if missing:
                raise ValueError(f"{fund.fund_id} cites unknown documents: {sorted(missing)}")
            periods = [item.period_years for item in fund.historical_returns]
            if len(set(periods)) != len(periods):
                raise ValueError(f"{fund.fund_id} repeats a historical return period")
        return self

    def fund(self, fund_id: str) -> CatalogFund | None:
        return next((fund for fund in self.funds if fund.fund_id == fund_id), None)


def _percent(value: float) -> str:
    return f"{Decimal(str(value)) * 100:.2f}%"


def effective_expense_ratio(fund: CatalogFund, on: date) -> tuple[float, bool]:
    """Net ratio while the contractual waiver runs; gross once it has lapsed."""
    if fund.fees.fee_waiver == 0:
        return fund.fees.net_expense_ratio, False
    if on <= fund.fees.waiver_ends:
        return fund.fees.net_expense_ratio, True
    return fund.fees.gross_expense_ratio, False


def to_fund_facts(fund: CatalogFund, catalog: FundCatalog, on: date) -> FundFacts:
    prospectus = catalog.documents[fund.prospectus_document]
    holdings = catalog.documents[fund.allocation.evidence.document]
    expense_ratio, waived = effective_expense_ratio(fund, on)
    if waived:
        fee_source = (f"{prospectus.title}: net of a {_percent(fund.fees.fee_waiver)} contractual waiver "
                      f"through {fund.fees.waiver_ends.isoformat()} (gross {_percent(fund.fees.gross_expense_ratio)})")
    else:
        fee_source = f"{prospectus.title}: total annual fund operating expenses"
    equity, bond, other = fund.allocation.weights()
    return FundFacts(
        fund_id=fund.fund_id,
        fund_type="target_date",
        currency=fund.currency,
        share_class_id=fund.share_class_id,
        name=fund.name,
        source=f"{holdings.title} (holdings as of {fund.allocation.as_of_date.isoformat()})",
        source_url=str(fund.allocation.evidence.url or holdings.url),
        prospectus_url=str(prospectus.url),
        as_of_date=fund.allocation.as_of_date,
        catalog_status=fund.catalog_status,
        expense_ratio=expense_ratio,
        expense_ratio_as_of_date=fund.fees.as_of_date,
        expense_ratio_source=fee_source,
        equity_weight=float(equity),
        bond_weight=float(bond),
        other_weight=float(other),
        target_year=fund.target_year,
        historical_returns=[
            HistoricalReturn(
                period_years=item.period_years,
                annualized_return_rate=item.annualized_return_rate,
                as_of_date=item.as_of_date,
                source=f"{catalog.documents[item.evidence.document].title}: {item.evidence.locator}",
            )
            for item in fund.historical_returns
        ],
    )


def parse_catalog(raw: bytes | str) -> FundCatalog:
    catalog = FundCatalog.model_validate(json.loads(raw))
    for fund in catalog.funds:  # prove every record converts before anyone can publish it
        to_fund_facts(fund, catalog, catalog.published_on)
    return catalog


def publish_catalog(raw: bytes | str, path: Path = DEFAULT_CATALOG_PATH) -> FundCatalog:
    """Validate, then atomically replace ``path``; a failure leaves the previous file untouched."""
    catalog = parse_catalog(raw)
    data = raw.encode("utf-8") if isinstance(raw, str) else raw
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    except BaseException:
        Path(temp).unlink(missing_ok=True)
        raise
    return catalog


class CatalogStore:
    """Serves the last valid snapshot; a failed reload keeps it and records why."""

    def __init__(self, path: Path = DEFAULT_CATALOG_PATH):
        self.path = path
        self._lock = threading.Lock()
        self._catalog: FundCatalog | None = None
        self._mtime: float | None = None
        self.last_error: str | None = None

    def current(self) -> FundCatalog | None:
        try:
            mtime = self.path.stat().st_mtime
        except OSError as exc:
            return self._keep(f"catalog unreadable: {type(exc).__name__}")
        if self._catalog is not None and mtime == self._mtime:
            return self._catalog
        with self._lock:
            if self._catalog is not None and mtime == self._mtime:
                return self._catalog
            try:
                catalog = parse_catalog(self.path.read_bytes())
            except Exception as exc:  # keep serving the previous snapshot
                self._mtime = mtime
                return self._keep(f"catalog rejected: {type(exc).__name__}")
            self._catalog, self._mtime, self.last_error = catalog, mtime, None
            return catalog

    def _keep(self, reason: str) -> FundCatalog | None:
        if reason != self.last_error:
            log.warning("fund %s; %s", reason,
                        "serving previous snapshot" if self._catalog else "no snapshot available")
        self.last_error = reason
        return self._catalog
