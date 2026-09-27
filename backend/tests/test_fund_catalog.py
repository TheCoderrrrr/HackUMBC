"""Reviewed fund catalog: evidence rules, FundFacts adapter, atomic publication, shortlist API."""

import copy
import json
import os
from datetime import date

import pytest
from pydantic import ValidationError

from app.fund_catalog import (
    DEFAULT_CATALOG_PATH, CatalogStore, parse_catalog, publish_catalog, to_fund_facts,
)
from .conftest import make_client

TODAY = date(2026, 9, 26)


@pytest.fixture
def raw():
    return json.loads(DEFAULT_CATALOG_PATH.read_text(encoding="utf-8"))


@pytest.fixture
def client():
    client = make_client()
    client.app.state.fund_today = lambda: TODAY
    return client


def dump(data) -> str:
    return json.dumps(data)


def test_shipped_catalog_converts_every_fund_with_exact_class_identity(raw):
    catalog = parse_catalog(dump(raw))
    assert len({fund.issuer for fund in catalog.funds}) >= 2
    for fund in catalog.funds:
        facts = to_fund_facts(fund, catalog, TODAY)
        assert facts.share_class_id == fund.share_class_id
        assert abs(facts.equity_weight + facts.bond_weight + facts.other_weight - 1) < 1e-9
        assert facts.expense_ratio == fund.fees.net_expense_ratio
        assert str(facts.prospectus_url).startswith("https://www.sec.gov/Archives/edgar/data/")


def test_fee_table_arithmetic_must_hold(raw):
    raw["funds"][0]["fees"]["net_expense_ratio"] = 0.0005
    with pytest.raises(ValidationError, match="gross expense ratio minus waiver"):
        parse_catalog(dump(raw))


def test_allocation_that_is_mostly_unclassified_is_rejected(raw):
    raw["funds"][0]["allocation"]["reported_categories"] = [
        {"label": "Equity Funds", "percent_of_net_assets": 50.0, "bucket": "equity"},
        {"label": "Alternatives", "percent_of_net_assets": 50.0, "bucket": "other"},
    ]
    with pytest.raises(ValidationError, match="ambiguous"):
        parse_catalog(dump(raw))


def test_every_datum_must_cite_a_known_document(raw):
    raw["funds"][0]["allocation"]["evidence"]["document"] = "not-a-filing"
    with pytest.raises(ValidationError, match="unknown documents"):
        parse_catalog(dump(raw))


def test_duplicate_share_class_is_rejected(raw):
    raw["funds"].append({**copy.deepcopy(raw["funds"][0]), "fund_id": "copy-of-first"})
    with pytest.raises(ValidationError, match="share class"):
        parse_catalog(dump(raw))


def test_gross_expense_ratio_applies_once_the_waiver_lapses(raw):
    catalog = parse_catalog(dump(raw))
    fund = catalog.funds[0]
    after = date.fromordinal(fund.fees.waiver_ends.toordinal() + 1)
    facts = to_fund_facts(fund, catalog, after)
    assert facts.expense_ratio == fund.fees.gross_expense_ratio
    assert "total annual fund operating expenses" in facts.expense_ratio_source


def test_failed_publish_keeps_previous_file(raw, tmp_path):
    path = tmp_path / "catalog.json"
    publish_catalog(dump(raw), path)
    before = path.read_bytes()
    broken = copy.deepcopy(raw)
    broken["funds"][0]["fees"]["gross_expense_ratio"] = 0.5
    with pytest.raises(ValidationError):
        publish_catalog(dump(broken), path)
    assert path.read_bytes() == before
    assert [p.name for p in tmp_path.iterdir()] == ["catalog.json"]


def test_store_serves_last_valid_snapshot_after_bad_refresh(raw, tmp_path):
    path = tmp_path / "catalog.json"
    publish_catalog(dump(raw), path)
    store = CatalogStore(path)
    first = store.current()
    path.write_text("{not json", encoding="utf-8")
    os.utime(path, (1, 1))
    assert store.current() is first
    assert store.last_error == "catalog rejected: JSONDecodeError"


def test_ira_shortlist_is_labeled_unconfirmed_and_carries_evidence(client):
    response = client.post("/v1/funds/shortlist", json={
        "account_type": "ira", "retirement_year": 2055, "risk_tolerance": "growth",
    })
    assert response.status_code == 200
    body = response.json()
    recs = body["shortlist"]["recommendations"]
    assert recs and {r["availability_label"] for r in recs} == {"discoverable_not_confirmed_purchasable"}
    assert recs[0]["target_year"] == 2055
    detail = body["details"][recs[0]["fund_id"]]
    assert detail["fees"]["waiver_active"] is True
    assert detail["prospectus"]["url"].startswith("https://www.sec.gov/")
    assert detail["allocation"]["as_of_date"] == "2026-06-30"
    assert "not forecasts" in body["shortlist"]["hypothetical_disclosure"]


def test_401k_menu_limits_results_and_reports_unknown_ids(client):
    response = client.post("/v1/funds/shortlist", json={
        "account_type": "401k", "retirement_year": 2030, "risk_tolerance": "moderate",
        "plan_menu_fund_ids": ["state-street-target-retirement-2030-k", "made-up-fund"],
    })
    body = response.json()
    assert [r["fund_id"] for r in body["shortlist"]["recommendations"]] == ["state-street-target-retirement-2030-k"]
    assert body["shortlist"]["plan_menu_status"] == "confirmed"
    assert body["unmatched_plan_menu_ids"] == ["made-up-fund"]


def test_401k_without_menu_returns_research_candidates(client):
    body = client.post("/v1/funds/shortlist", json={
        "account_type": "401k", "retirement_year": 2035, "risk_tolerance": "moderate",
    }).json()
    assert body["shortlist"]["plan_menu_status"] == "unknown"
    assert {r["availability_label"] for r in body["shortlist"]["recommendations"]} == {
        "research_candidate_plan_menu_unconfirmed"}


def test_stale_holdings_are_excluded_not_ranked(client):
    client.app.state.fund_today = lambda: date(2027, 1, 15)
    body = client.post("/v1/funds/shortlist", json={
        "account_type": "ira", "retirement_year": 2055, "risk_tolerance": "growth",
    }).json()
    assert body["shortlist"]["recommendations"] == []
    assert {e["reason_code"] for e in body["shortlist"]["excluded"]} == {"STALE_FACTS"}


def test_out_of_range_retirement_year_uses_error_envelope(client):
    response = client.post("/v1/funds/shortlist", json={
        "account_type": "ira", "retirement_year": 2020, "risk_tolerance": "growth",
    })
    assert response.status_code == 422
    assert response.json()["error"]["field_paths"] == ["retirement_year"]


def test_missing_catalog_is_retryable_503(client, tmp_path):
    client.app.state.fund_catalog = CatalogStore(tmp_path / "absent.json")
    response = client.get("/v1/funds/catalog")
    assert response.status_code == 503
    assert response.json()["error"] == {
        "code": "FUND_CATALOG_UNAVAILABLE", "message": "The reviewed fund catalog is not available right now.",
        "field_paths": [], "retryable": True,
    }


def test_catalog_summary_lists_reviewed_funds(client, raw):
    body = client.get("/v1/funds/catalog").json()
    assert body["catalog_version"] == raw["catalog_version"]
    assert [f["fund_id"] for f in body["funds"]] == [f["fund_id"] for f in raw["funds"]]
