"""Fund shortlist eligibility, ranking, and hypothetical return boundaries."""

import pytest
from pydantic import ValidationError

from app.funds import FundShortlistRequest, shortlist_funds


def fund(fund_id="a", **changes):
    data = {
        "fund_id": fund_id,
        "fund_type": "target_date",
        "currency": "USD",
        "share_class_id": f"{fund_id}-class",
        "name": f"Synthetic {fund_id}",
        "source": "caller catalog",
        "source_url": "https://catalog.example.test/funds",
        "prospectus_url": "https://catalog.example.test/prospectus",
        "as_of_date": "2026-09-26",
        "catalog_status": "listed",
        "expense_ratio": .002,
        "expense_ratio_as_of_date": "2026-09-26",
        "expense_ratio_source": "caller fee document",
        "equity_weight": .6,
        "bond_weight": .4,
        "other_weight": 0.0,
        "target_year": 2045,
        "historical_returns": [],
    }
    data.update(changes)
    return data


def request(catalog, *, account_type="ira", menu=None, risk="moderate", max_results=3):
    return FundShortlistRequest.model_validate({
        "account_type": account_type,
        "as_of_date": "2026-09-26",
        "retirement_year": 2045,
        "risk_tolerance": risk,
        "plan_menu_fund_ids": menu,
        "catalog": catalog,
        "max_results": max_results,
    })


def test_401k_recommends_only_supplied_plan_menu_members():
    result = shortlist_funds(request(
        [fund("on-menu"), fund("outside", expense_ratio=0)],
        account_type="401k", menu=["on-menu"],
    ))
    assert [item.fund_id for item in result.recommendations] == ["on-menu"]
    assert result.recommendations[0].availability_label == "in_supplied_plan_menu"
    assert [(item.fund_id, item.reason_code) for item in result.excluded] == [
        ("outside", "NOT_IN_PLAN_MENU")
    ]


def test_ira_is_discoverable_without_purchase_claim_and_results_capped():
    result = shortlist_funds(request([fund(str(i)) for i in range(5)]))
    assert len(result.recommendations) == 3
    assert all(item.availability_label == "discoverable_not_confirmed_purchasable"
               for item in result.recommendations)
    assert "do not confirm purchase eligibility" in result.hypothetical_disclosure
    assert [item.fund_id for item in result.recommendations] == ["0", "1", "2"]


def test_explicit_risk_tolerance_changes_ranking_independent_of_age_or_debt():
    catalog = [
        fund("cautious", equity_weight=.4, bond_weight=.6),
        fund("growth", equity_weight=.8, bond_weight=.2),
    ]
    assert shortlist_funds(request(catalog, risk="conservative")).recommendations[0].fund_id == "cautious"
    assert shortlist_funds(request(catalog, risk="growth")).recommendations[0].fund_id == "growth"


def test_horizon_and_fees_affect_transparent_deterministic_score():
    catalog = [
        fund("low-fee", expense_ratio=.001),
        fund("high-fee", expense_ratio=.008),
        fund("wrong-year", expense_ratio=.001, target_year=2070),
    ]
    result = shortlist_funds(request(catalog))
    assert [item.fund_id for item in result.recommendations] == ["low-fee", "high-fee"]
    assert result.recommendations[0].score_components.fee_fit > result.recommendations[1].score_components.fee_fit
    assert ("wrong-year", "POOR_HORIZON_FIT") in {
        (item.fund_id, item.reason_code) for item in result.excluded
    }
    assert sum(result.score_weights.values()) == pytest.approx(1)


def test_stale_incomplete_and_unavailable_rows_are_excluded():
    catalog = [
        fund("fresh"),
        fund("stale", as_of_date="2026-01-01"),
        fund("missing", equity_weight=None),
        fund("unavailable", catalog_status="unavailable"),
    ]
    result = shortlist_funds(request(catalog))
    assert [item.fund_id for item in result.recommendations] == ["fresh"]
    assert {(item.fund_id, item.reason_code) for item in result.excluded} == {
        ("stale", "STALE_FACTS"),
        ("missing", "INCOMPLETE_FACTS"),
        ("unavailable", "UNAVAILABLE"),
    }


def test_hypothetical_paths_are_net_of_fee_and_history_stays_separate():
    history = [{
        "period_years": 3, "annualized_return_rate": .20,
        "as_of_date": "2026-09-26", "source": "caller history",
    }]
    result = shortlist_funds(request([fund("mix", historical_returns=history)]))
    rec = result.recommendations[0]
    low, base, high = rec.hypothetical_scenarios
    assert [item.label for item in rec.hypothetical_scenarios] == ["low", "base", "high"]
    assert base.annual_net_return_rate == pytest.approx(.6 * .06 + .4 * .03 - .002)
    assert low.hypothetical_end_cents < base.hypothetical_end_cents < high.hypothetical_end_cents
    assert base.hypothetical_start_cents == 1_000_000
    assert base.years == 19
    assert rec.historical_returns[0].annualized_return_rate == .20
    assert all(item.annual_net_return_rate != .20 for item in rec.hypothetical_scenarios)
    assert "not forecasts or guarantees" in result.hypothetical_disclosure
    assert "weights constant through the horizon" in result.hypothetical_disclosure
    assert "not provider forecasts" in result.hypothetical_disclosure
    assert all(item.allocation_assumption == "current_weights_held_constant"
               for item in rec.hypothetical_scenarios)


def test_stale_history_is_omitted_without_inventing_replacement():
    old = [{
        "period_years": 5, "annualized_return_rate": .07,
        "as_of_date": "2020-01-01", "source": "old facts",
    }]
    result = shortlist_funds(request([fund("a", historical_returns=old)]))
    rec = result.recommendations[0]
    assert rec.historical_returns == []
    assert "HISTORY_NOT_SUPPLIED" in rec.reason_codes
    assert rec.score_components.data_completeness == .8


def test_current_holdings_can_use_annual_fee_document_with_separate_provenance():
    catalog = [
        fund("annual-fee", expense_ratio_as_of_date="2025-12-31",
             expense_ratio_source="annual prospectus"),
        fund("ancient-fee", expense_ratio_as_of_date="2024-01-01"),
    ]
    result = shortlist_funds(request(catalog))
    assert [item.fund_id for item in result.recommendations] == ["annual-fee"]
    rec = result.recommendations[0]
    assert rec.expense_ratio_source == "annual prospectus"
    assert rec.expense_ratio_as_of_date.isoformat() == "2025-12-31"
    assert [(item.fund_id, item.reason_code) for item in result.excluded] == [
        ("ancient-fee", "STALE_FACTS")
    ]


@pytest.mark.parametrize("change", [
    {"equity_weight": .8},
    {"expense_ratio": -0.01},
    {"expense_ratio": float("nan")},
    {"target_year": None, "historical_returns": [{"period_years": 1,
        "annualized_return_rate": float("inf"), "as_of_date": "2026-09-26", "source": "bad"}]},
])
def test_invalid_supplied_facts_are_rejected(change):
    with pytest.raises(ValidationError):
        request([fund("bad", **change)])


def test_request_rejects_duplicate_catalog_ids_and_untrusted_profile_fields():
    with pytest.raises(ValidationError):
        request([fund("same"), fund("same")])
    payload = request([fund("one")]).model_dump(mode="json")
    payload["age"] = 35
    with pytest.raises(ValidationError):
        FundShortlistRequest.model_validate(payload)
    with pytest.raises(ValidationError):
        request([fund(" ")])
    assert shortlist_funds(request([fund("blank-name", name=" ")])).excluded[0].reason_code == "INCOMPLETE_FACTS"


def test_fund_type_currency_share_class_and_urls_gate_ranking():
    result = shortlist_funds(request([
        fund("good"),
        fund("ordinary", fund_type="other"),
        fund("foreign", currency="EUR"),
        fund("no-class", share_class_id=None),
        fund("no-source-url", source_url=None),
        fund("no-prospectus", prospectus_url=None),
    ]))
    assert [item.fund_id for item in result.recommendations] == ["good"]
    good = result.recommendations[0]
    assert good.fund_type == "target_date" and good.currency == "USD"
    assert good.share_class_id == "good-class"
    assert str(good.source_url).startswith("https://")
    assert str(good.prospectus_url).startswith("https://")
    assert {(item.fund_id, item.reason_code) for item in result.excluded} == {
        ("ordinary", "NOT_TARGET_DATE"), ("foreign", "NON_USD"),
        ("no-class", "INCOMPLETE_FACTS"), ("no-source-url", "INCOMPLETE_FACTS"),
        ("no-prospectus", "INCOMPLETE_FACTS"),
    }


def test_other_allocation_is_validated_and_used_in_disclosed_scenario():
    row = fund("other-slice", equity_weight=.5, bond_weight=.4, other_weight=.1)
    rec = shortlist_funds(request([row])).recommendations[0]
    assert rec.other_weight == .1
    assert rec.risk_band in range(1, 6)
    assert rec.risk_method == "current_equity_weight_proxy_not_volatility"
    assert rec.risk_inputs == {"equity_weight": .5, "bond_weight": .4, "other_weight": .1}
    base = rec.hypothetical_scenarios[1]
    assert base.other_assumption_rate == 0
    assert base.annual_net_return_rate == pytest.approx(.5 * .06 + .4 * .03 - .002)
    with pytest.raises(ValidationError):
        request([fund("bad-mix", equity_weight=.5, bond_weight=.4, other_weight=.05)])


def test_zero_horizon_or_risk_fit_cannot_rank():
    result = shortlist_funds(request([
        fund("good"),
        fund("horizon-zero", target_year=2065),
        fund("risk-zero", equity_weight=0, bond_weight=1),
    ], risk="growth"))
    assert [item.fund_id for item in result.recommendations] == ["good"]
    assert {(item.fund_id, item.reason_code) for item in result.excluded} == {
        ("horizon-zero", "POOR_HORIZON_FIT"),
        ("risk-zero", "POOR_RISK_FIT"),
    }


def test_fee_provenance_is_required_and_never_filled_from_holdings_source():
    result = shortlist_funds(request([
        fund("complete"),
        fund("missing-fee-source", expense_ratio_source=None),
        fund("missing-fee-date", expense_ratio_as_of_date=None),
    ]))
    assert [item.fund_id for item in result.recommendations] == ["complete"]
    assert {(item.fund_id, item.reason_code) for item in result.excluded} == {
        ("missing-fee-source", "INCOMPLETE_FACTS"),
        ("missing-fee-date", "INCOMPLETE_FACTS"),
    }


def test_unknown_401k_menu_is_research_only_while_confirmed_empty_is_empty():
    catalog = [fund("candidate")]
    unknown = shortlist_funds(request(catalog, account_type="401k", menu=None))
    assert unknown.plan_menu_status == "unknown"
    assert unknown.recommendations[0].availability_label == "research_candidate_plan_menu_unconfirmed"
    empty = shortlist_funds(request(catalog, account_type="401k", menu=[]))
    assert empty.plan_menu_status == "confirmed"
    assert empty.recommendations == []
    assert empty.excluded[0].reason_code == "NOT_IN_PLAN_MENU"


def test_hypothetical_assumption_set_has_version_and_date():
    result = shortlist_funds(request([fund("candidate")]))
    assert result.assumption_set_version == "prototype-1.0.0"
    assert result.assumption_set_as_of_date.isoformat() == "2026-09-26"
    assert "prototype policy constants" in result.hypothetical_disclosure
