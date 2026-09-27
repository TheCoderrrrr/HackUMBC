"""Server-owned, dated fund assumptions used by every evaluation surface."""
from __future__ import annotations

from copy import deepcopy
from datetime import date

from app.engine.assumptions import MODEL_ASSUMPTIONS
from app.errors import ApiError
from app.fund_catalog import CatalogStore, FundCatalog, effective_expense_ratio
from app.schemas import FinancialProfile, FundModel, GlidePathAnchor

_store = CatalogStore()


def resolve(profile: FinancialProfile, catalog: FundCatalog | None = None) -> dict:
    assumptions = deepcopy(MODEL_ASSUMPTIONS)
    if not profile.fund_id:
        return assumptions
    catalog = catalog or _store.current()
    if catalog is None:
        raise ApiError(503, "FUND_CATALOG_UNAVAILABLE", "The reviewed fund catalog is unavailable.", retryable=True)
    fund = catalog.fund(profile.fund_id)
    if fund is None or fund.catalog_status != "listed":
        raise ApiError(422, "UNKNOWN_FUND", "Choose a listed target-date fund.", ["profile.fund_id"])
    if profile.fund_account_type == "401k" and profile.plan_menu_fund_ids is not None and fund.fund_id not in profile.plan_menu_fund_ids:
        raise ApiError(422, "FUND_NOT_IN_MENU", "The selected fund is not in your plan menu.", ["profile.fund_id"])
    fee, _ = effective_expense_ratio(fund, profile.as_of_date)
    fee_doc = catalog.documents[fund.fees.evidence.document]
    glide_doc = catalog.documents[fund.glide_path.evidence.document]
    anchors = fund.glide_path.anchors
    documented = anchors is not None
    model = FundModel(
        fund_id=fund.fund_id, fund_name=fund.name, catalog_version=catalog.catalog_version,
        share_class_id=fund.share_class_id, target_year=fund.target_year,
        applied_expense_ratio=fee, fee_as_of_date=fund.fees.as_of_date,
        fee_source_url=str(fund.fees.evidence.url or fee_doc.url),
        glide_path_source_url=str(fund.glide_path.evidence.url or glide_doc.url),
        glide_path_mode="documented" if documented else "generic_fallback",
        glide_path=[GlidePathAnchor(years_to_retirement=y, equity_weight=w) for y, w in anchors] if anchors else
                   [GlidePathAnchor(**a) for a in MODEL_ASSUMPTIONS["glide_path"]],
        limitation=None if documented else "The issuer record lacks numeric glide-path anchors; the generic retirement-age path is used.",
    )
    assumptions["fund_model"] = model.model_dump(mode="json")
    assumptions["returns_net_of_fees"] = False
    assumptions["limitations"] = [
        "Illustrative asset-class returns are not fund forecasts; annual fund expense is deducted separately.",
        *MODEL_ASSUMPTIONS["limitations"][1:],
    ]
    if model.limitation:
        assumptions["limitations"].append(model.limitation)
    return assumptions


def weight(model: FundModel, as_of: date, month: int, remaining_months: int) -> float:
    if model.glide_path_mode == "generic_fallback":
        years = remaining_months / 12
    else:
        years = model.target_year - (as_of.year + (as_of.month - 1 + month - 1) / 12)
    anchors = sorted(model.glide_path, key=lambda a: a.years_to_retirement)
    if years <= anchors[0].years_to_retirement:
        return anchors[0].equity_weight
    for left, right in zip(anchors, anchors[1:]):
        if years <= right.years_to_retirement:
            part = (years - left.years_to_retirement) / (right.years_to_retirement - left.years_to_retirement)
            return left.equity_weight + part * (right.equity_weight - left.equity_weight)
    return anchors[-1].equity_weight
