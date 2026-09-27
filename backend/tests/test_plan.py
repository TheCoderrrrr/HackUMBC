"""Public first-month action and deterministic explanation contract."""

import json
from copy import deepcopy

import pytest

from app.engine.explanations import render_reason, template_explanation
from app.engine.policy import build_plan, default_priorities, validate_decision
from app.engine.state import derive_state


ACTION_FIELDS = {"id", "rank", "category", "status", "monthly_cash_cost_cents",
                 "employee_contribution_cents", "employee_contribution_rate", "debt_id",
                 "target_balance_cents", "reason_codes"}
REASON_FIELDS = {"code", "template_key", "facts", "input_paths"}


def public_result(profile):
    state = derive_state(profile)
    decision = validate_decision(profile, state, None)
    plan = build_plan(profile, state, decision)
    return state, decision, plan


def resolve_path(profile, path):
    value = profile
    for part in path.split("."):
        value = value[int(part)] if isinstance(value, list) else value[part]
    return value


def test_morgan_debt_headline_and_grounded_facts(morgan):
    state, decision, plan = public_result(morgan)
    assert decision["source"] == "rules_fallback"
    assert plan["primary_action_id"] == "debt-morgan-card"
    debt = next(action for action in plan["actions"] if action["id"] == "debt-morgan-card")
    assert debt["monthly_cash_cost_cents"] == 136380
    assert debt["status"] == "action"
    facts = next(reason["facts"] for reason in plan["reasons"] if reason["code"] == "HIGH_APR_DEBT")
    assert facts == {"debt_id": "morgan-card", "debt_type": "credit_card", "balance_cents": 1800000,
                     "apr_rate": .25, "minimum_payment_cents": 40000,
                     "extra_payment_cents": 96380, "total_payment_cents": 136380}
    explanation = template_explanation(morgan, state, decision, plan)
    assert explanation["source"] == "template"
    assert "$963.80" in explanation["narrative"]
    assert explanation["changes"] == []


@pytest.mark.parametrize("name", ["jordan", "casey"])
def test_established_profile_maintenance(profiles, name):
    profile = deepcopy(profiles[name])
    _, _, plan = public_result(profile)
    contribution = next(action for action in plan["actions"] if action["id"] == "employee-contribution")
    assert contribution["status"] == "maintain"
    assert "MAINTAIN_CONTRIBUTION" in contribution["reason_codes"]
    assert plan["primary_action_id"] == "employee-contribution"
    assert not any(reason["code"] == "HIGH_APR_DEBT" for reason in plan["reasons"])


def test_critical_reserve_is_primary_and_gap_only(morgan):
    morgan["emergency_cash_cents"] = 99999
    _, _, plan = public_result(morgan)
    assert plan["primary_action_id"] == "critical-reserve"
    critical = next(action for action in plan["actions"] if action["id"] == "critical-reserve")
    assert critical["monthly_cash_cost_cents"] == 1


def test_affordable_missing_match_increase_precedes_debt(morgan):
    morgan["employee_contribution_rate"] = 0
    _, _, plan = public_result(morgan)
    assert plan["primary_action_id"] == "employee-contribution"
    contribution = next(action for action in plan["actions"] if action["id"] == "employee-contribution")
    assert contribution["status"] == "action"
    assert contribution["employee_contribution_cents"] == 35000
    assert "CAPTURE_EMPLOYER_MATCH" in contribution["reason_codes"]


@pytest.mark.parametrize("preference,cash,expected", [
    ("balanced", 360000, "debt-morgan-card"),
    ("cash_security", 360000, "full-reserve"),
    ("debt_reduction", 360000, "debt-morgan-card"),
    ("balanced", 200000, "starter-reserve"),
    ("debt_reduction", 200000, "debt-morgan-card"),
])
def test_preference_primary_when_both_compete(morgan, preference, cash, expected):
    morgan["planning_preference"] = preference
    morgan["emergency_cash_cents"] = cash
    _, decision, plan = public_result(morgan)
    assert decision["ordered_priorities"] == list(default_priorities(preference))
    assert plan["primary_action_id"] == expected


@pytest.mark.parametrize("kind", ["missing", "shortfall", "both"])
def test_blocked_plan_has_no_unfunded_actions(morgan, kind):
    if kind in {"missing", "both"}:
        morgan["employer_match"] = {"status": "unknown", "fully_vested": False, "tiers": []}
    if kind in {"shortfall", "both"}:
        morgan["monthly_take_home_cents"] = 0
    _, _, plan = public_result(morgan)
    assert all(action["status"] == "blocked" and action["monthly_cash_cost_cents"] == 0
               for action in plan["actions"])
    assert plan["primary_action_id"] == plan["actions"][0]["id"]
    codes = {reason["code"] for reason in plan["reasons"]}
    assert ("MISSING_REQUIRED_INPUT" in codes) == (kind in {"missing", "both"})
    assert ("CASH_FLOW_SHORTFALL" in codes) == (kind in {"shortfall", "both"})


@pytest.mark.parametrize("fixture", ["jordan", "morgan", "casey"])
def test_action_and_reason_contract_and_cash_identity(profiles, fixture):
    profile = deepcopy(profiles[fixture])
    original = deepcopy(profile)
    state, decision, plan = public_result(profile)
    assert profile == original
    assert plan["primary_action_id"] in {item["id"] for item in plan["actions"]}
    assert len({item["id"] for item in plan["actions"]}) == len(plan["actions"])
    assert [item["rank"] for item in plan["actions"]] == list(range(1, len(plan["actions"]) + 1))
    assert len({item["code"] for item in plan["reasons"]}) == len(plan["reasons"])
    codes = {reason["code"] for reason in plan["reasons"]}
    for action in plan["actions"]:
        assert set(action) == ACTION_FIELDS
        assert type(action["monthly_cash_cost_cents"]) is int
        assert action["monthly_cash_cost_cents"] >= 0
        assert action["reason_codes"] and set(action["reason_codes"]) <= codes
    for reason in plan["reasons"]:
        assert set(reason) == REASON_FIELDS
        assert reason["template_key"] == reason["code"].lower()
        assert reason["input_paths"]
        for path in reason["input_paths"]:
            resolve_path(profile, path)
        assert all(value is None or type(value) in {str, int, float, bool}
                   for value in reason["facts"].values())
        json.dumps(reason["facts"], allow_nan=False)
        assert render_reason(reason).strip()
    assert sum(action["monthly_cash_cost_cents"] for action in plan["actions"]) == (
        state["monthly_resources_before_retirement_cents"] - profile["monthly_living_expenses_cents"]
    )
    json.dumps(plan, allow_nan=False)
    explanation = template_explanation(profile, state, decision, plan)
    assert explanation["source"] == "template"
    assert explanation["narrative"].strip() and explanation["state_summary"].strip()


def test_contribution_decrease_does_not_claim_maintenance(morgan):
    morgan["monthly_take_home_cents"] = 380000
    _, _, plan = public_result(morgan)
    contribution = next(item for item in plan["actions"] if item["id"] == "employee-contribution")
    assert contribution["employee_contribution_cents"] < 56000
    assert contribution["status"] == "action"
    assert "MAINTAIN_CONTRIBUTION" not in contribution["reason_codes"]
    assert "MAINTAIN_CONTRIBUTION" not in {reason["code"] for reason in plan["reasons"]}


def test_all_reason_templates_cover_varied_plan_shapes(morgan):
    variants = []
    variants.append(deepcopy(morgan))
    critical = deepcopy(morgan)
    critical["emergency_cash_cents"] = 0
    variants.append(critical)
    partial = deepcopy(morgan)
    partial["monthly_take_home_cents"] = 380000
    variants.append(partial)
    increase = deepcopy(morgan)
    increase["debts"] = []
    increase["emergency_cash_cents"] = 1080000
    increase["employee_contribution_rate"] = 0
    variants.append(increase)
    blocked = deepcopy(morgan)
    blocked["monthly_take_home_cents"] = 0
    variants.append(blocked)
    cash_first = deepcopy(morgan)
    cash_first["planning_preference"] = "cash_security"
    variants.append(cash_first)
    for profile in variants:
        state, decision, plan = public_result(profile)
        for reason in plan["reasons"]:
            assert render_reason(reason).strip()
        assert template_explanation(profile, state, decision, plan)["source"] == "template"


def test_adjust_contribution_template_and_unknown_code_error():
    adjusted = {"code": "ADJUST_CONTRIBUTION", "facts": {
        "original_employee_contribution_cents": 56000,
        "employee_contribution_cents": 35000,
    }}
    assert "$560.00" in render_reason(adjusted)
    assert "$350.00" in render_reason(adjusted)
    with pytest.raises(ValueError, match="No template for reason code"):
        render_reason({"code": "UNSUPPORTED", "facts": {}})


def test_allocation_wording_is_illustrative(morgan):
    _, _, plan = public_result(morgan)
    reason = next(item for item in plan["reasons"] if item["code"] == "BASELINE_ALLOCATION_RETAINED")
    rendered = render_reason(reason)
    assert "illustrative" in rendered.lower()
    assert "No personal portfolio optimization" in rendered


def test_recorded_changes_preserve_values_without_aliasing(morgan):
    state, decision, plan = public_result(morgan)
    changes = [{"field_path": "financial_state.emergency_months", "before": 0.5, "after": 1.0}]
    original = deepcopy(changes)
    explanation = template_explanation(morgan, state, decision, plan, changes)
    assert explanation["changes"] == original
    assert explanation["source"] == "template"
    assert "recorded changes" in explanation["narrative"]
    assert "$" in explanation["state_summary"]
    explanation["changes"][0]["after"] = 3.0
    assert changes == original


def test_negative_amortization_does_not_invent_plan_amounts(morgan):
    morgan["debts"][0]["minimum_payment_cents"] = 100
    morgan["emergency_cash_cents"] = 0
    morgan["monthly_take_home_cents"] = 360100
    state, decision, plan = public_result(morgan)
    debt = next(action for action in plan["actions"] if action["id"] == "debt-morgan-card")
    assert debt["monthly_cash_cost_cents"] == 100
    text = template_explanation(morgan, state, decision, plan)["narrative"]
    assert "$" in text
    assert "$375.00" not in text


@pytest.mark.parametrize("kind", ["zero_available", "no_match_zero_cap"])
def test_primary_always_exists_for_valid_zero_cash_edges(morgan, kind):
    if kind == "zero_available":
        morgan["monthly_take_home_cents"] = 356320
    else:
        morgan["employer_match"] = {"status": "none", "fully_vested": True, "tiers": []}
        morgan["employee_contribution_rate"] = 0
        morgan["annual_employee_limit_cents"] = 0
        morgan["debts"] = []
        morgan["emergency_cash_cents"] = 1080000
    state, decision, plan = public_result(morgan)
    assert plan["primary_action_id"] in {action["id"] for action in plan["actions"]}
    assert template_explanation(morgan, state, decision, plan)["narrative"].strip()
