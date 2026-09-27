from __future__ import annotations

from copy import deepcopy

from app import engine_port
from app.engine.simulation import run_simulation
from app.fund_model import resolve, weight
from app.schemas import FundModel, Scenario

from .conftest import make_client


FUND = "blackrock-lifepath-index-2055-k"


def selected_morgan():
    return engine_port.load_demo_profiles()[1].model_copy(update={
        "fund_id": FUND, "fund_balance_confirmed": True, "fund_account_type": "401k",
        "plan_menu_fund_ids": [FUND],
    })


def test_selected_fund_changes_projection_and_records_sources():
    profile = selected_morgan()
    plain = profile.model_copy(update={"fund_id": None, "fund_balance_confirmed": False,
                                       "fund_account_type": None, "plan_menu_fund_ids": None})
    state = engine_port.derive_state(profile)
    decision = engine_port.validate_decision(profile, state, None, prompt_version="2")
    fund_result = engine_port.evaluate(profile, None, decision)
    generic_result = engine_port.evaluate(plain, None, decision)
    fund = fund_result.assumptions.fund_model
    assert fund is not None and fund.fund_id == FUND
    assert fund.glide_path_mode == "documented"
    assert fund.fee_source_url.startswith("https://www.sec.gov/")
    assert fund_result.financial_state.baseline_equity_weight == weight(fund, profile.as_of_date, 1, 384)
    assert fund_result.projections.adaptive.retirement_balance_nominal_cents != generic_result.projections.adaptive.retirement_balance_nominal_cents
    assert fund_result.input_hash != generic_result.input_hash


def test_fund_fee_is_deducted_once():
    profile = selected_morgan()
    decision = engine_port.validate_decision(profile, engine_port.derive_state(profile), None, prompt_version="2")
    assumptions = resolve(profile)
    with_fee = run_simulation(profile, "adaptive", None, assumptions, decision).projection
    without_fee = deepcopy(assumptions)
    without_fee["fund_model"]["applied_expense_ratio"] = 0
    no_fee = run_simulation(profile, "adaptive", None, without_fee, decision).projection
    assert with_fee.retirement_balance_nominal_cents < no_fee.retirement_balance_nominal_cents


def test_missing_numeric_issuer_path_is_labeled_fallback():
    profile = selected_morgan().model_copy(update={"fund_id": "state-street-target-retirement-2055-k",
                                             "plan_menu_fund_ids": None})
    model = FundModel.model_validate(resolve(profile)["fund_model"])
    assert model.glide_path_mode == "generic_fallback"
    assert model.limitation


def test_scenario_pins_decision_and_uses_exact_debt_budget():
    profile = selected_morgan()
    client = make_client()
    base = client.post("/v1/evaluate", json={"profile": profile.model_dump(mode="json")}).json()
    assert base["rules_comparison"]["outcome"] == "equal"
    scenario = {"retirement_age": profile.retirement_age + 1,
                "employee_contribution_rate": None, "extra_monthly_debt_cents": 50_000,
                "priority_style": "debt_reduction"}
    response = client.post("/v1/evaluate", json={"profile": profile.model_dump(mode="json"),
                                                "scenario": scenario,
                                                "base_decision_id": base["decision_summary"]["decision_id"]})
    assert response.status_code == 200
    compared = response.json()
    assert compared["decision_summary"]["decision_id"] == base["decision_summary"]["decision_id"]
    assert compared["rules_comparison"]["basis"] == "custom"
    assert compared["projections"]["custom"]["feasible"]
    decision = engine_port.validate_decision(profile, engine_port.derive_state(profile), None, prompt_version="2")
    run = run_simulation(profile, "custom", Scenario.model_validate(scenario), resolve(profile), decision)
    assert sum(debt["extra_payment_cents"] for debt in run.opening_allocation.facts["raw_allocation"]["debts"]) == 50_000


def test_selected_fund_requires_balance_confirmation():
    raw = selected_morgan().model_dump(mode="json")
    raw["fund_balance_confirmed"] = False
    response = make_client().post("/v1/evaluate", json={"profile": raw})
    assert response.status_code == 422
