"""Independent regressions for review findings at decision and plan boundaries."""

import pytest

from app.engine.explanations import render_reason, template_explanation
from app.engine.policy import allocate_month, build_plan, default_priorities, validate_decision
from app.engine.state import derive_state


def fallback_plan(profile):
    state = derive_state(profile)
    decision = validate_decision(profile, state, None)
    return state, decision, build_plan(profile, state, decision)


def grounded_proposal(profile):
    order = list(default_priorities(profile.get("planning_preference", "balanced")))
    return {"ordered_priorities": order, "rationale": [
        {"priority": priority, "summary": "Use the stated financial indicators.",
         "evidence_paths": ["financial_state.emergency_months"],
         "tradeoff": "Cash used here is unavailable for another priority."}
        for priority in order
    ]}


def test_missing_match_increase_is_primary_even_when_above_full_match(morgan):
    morgan["employee_contribution_rate"] = 0
    morgan["monthly_take_home_cents"] = 800000
    morgan["emergency_cash_cents"] = 1080000
    morgan["debts"][0]["balance_cents"] = 100000
    state, decision, plan = fallback_plan(morgan)
    allocation = allocate_month(morgan, state, decision)
    assert allocation["employee_contribution_rate"] > .05
    assert allocation["debts"][0]["extra_payment_cents"] > 0
    assert plan["primary_action_id"] == "employee-contribution"


def test_critical_liquidity_discloses_exact_lost_match(morgan):
    morgan["emergency_cash_cents"] = 0
    morgan["monthly_take_home_cents"] = 356321
    state, decision, plan = fallback_plan(morgan)
    allocation = allocate_month(morgan, state, decision)
    assert plan["primary_action_id"] == "critical-reserve"
    assert allocation["cash_to_critical_reserve_cents"] == 1
    assert allocation["employer_match_cents"] < state["maximum_monthly_employer_match_cents"]
    reason = next(item for item in plan["reasons"] if item["code"] == "CRITICAL_LIQUIDITY")
    # The pre-reserve budget is one cent; only one cent of matching was
    # affordable without this reserve transfer, regardless of the full maximum.
    assert state["monthly_allocatable_budget_cents"] == 1
    foregone = 1
    assert state["maximum_monthly_employer_match_cents"] - allocation["employer_match_cents"] > foregone
    assert reason["facts"]["foregone_employer_match_cents"] == foregone
    assert "employer match" in render_reason(reason).lower() or "employer matching" in render_reason(reason).lower()
    explanation = template_explanation(morgan, state, decision, plan)
    assert "employer match" in explanation["narrative"].lower() or "employer matching" in explanation["narrative"].lower()


def test_funded_critical_reserve_does_not_claim_lost_match(morgan):
    morgan["emergency_cash_cents"] = 100000
    state, decision, plan = fallback_plan(morgan)
    allocation = allocate_month(morgan, state, decision)
    assert allocation["employer_match_cents"] == state["maximum_monthly_employer_match_cents"]
    assert not any(reason["code"] == "CRITICAL_LIQUIDITY" for reason in plan["reasons"])


@pytest.mark.parametrize("take_home,expected_foregone", [(480000, 10000), (560000, 0)])
def test_critical_match_tradeoff_is_limited_by_cap_and_actual_cash(
    morgan, take_home, expected_foregone
):
    morgan["employee_contribution_rate"] = 0
    morgan["annual_employee_limit_cents"] = 120000
    morgan["emergency_cash_cents"] = 0
    morgan["monthly_take_home_cents"] = take_home
    state, decision, plan = fallback_plan(morgan)
    allocation = allocate_month(morgan, state, decision)
    assert allocation["employer_match_cents"] == (0 if take_home == 480000 else 10000)
    critical = next(reason for reason in plan["reasons"] if reason["code"] == "CRITICAL_LIQUIDITY")
    assert critical["facts"]["foregone_employer_match_cents"] == expected_foregone
    narrative = template_explanation(morgan, state, decision, plan)["narrative"].lower()
    if expected_foregone:
        assert "employer match" in narrative or "employer matching" in narrative
    else:
        assert "sacrific" not in narrative and "forego" not in narrative
    contribution = next(action for action in plan["actions"] if action["id"] == "employee-contribution")
    assert "MATCH_PARTIALLY_AFFORDABLE" in contribution["reason_codes"]


@pytest.mark.parametrize("unsafe_text", [
    "Contribute $999,999,999 this month.",
    "Contribute 900 dollars every month.",
    "A 99% return is guaranteed.",
    "Nine hundred dollars is the correct contribution.",
    "Your retirement is guaranteed and you are ready.",
    "People your age always need this plan.",
])
def test_unsupported_model_claims_fall_back(morgan, unsafe_text):
    raw = grounded_proposal(morgan)
    raw["rationale"][0]["summary"] = unsafe_text
    state = derive_state(morgan)
    result = validate_decision(morgan, state, raw, model_id="review-model")
    assert result["source"] == "rules_fallback"
    assert result["fallback_reason"] is not None
    assert unsafe_text not in str(result)


def test_ordinary_english_rationale_is_accepted(morgan):
    # "a certain buffer" is ordinary English, not a certainty claim (REPORT C4).
    raw = grounded_proposal(morgan)
    raw["rationale"][0]["summary"] = "A certain buffer comes before extra debt payments."
    state = derive_state(morgan)
    result = validate_decision(morgan, state, raw, model_id="review-model")
    assert result["source"] == "ai"
    assert result["fallback_reason"] is None


def test_certainty_claims_still_fall_back(morgan):
    raw = grounded_proposal(morgan)
    raw["rationale"][0]["summary"] = "This outcome is certainly safe."
    state = derive_state(morgan)
    result = validate_decision(morgan, state, raw, model_id="review-model")
    assert result["source"] == "rules_fallback"
    assert result["fallback_reason"] == "UNSUPPORTED_RATIONALE_CLAIM"


def test_qualitative_grounded_proposal_still_accepted(morgan):
    state = derive_state(morgan)
    result = validate_decision(morgan, state, grounded_proposal(morgan), model_id="review-model")
    assert result["source"] == "ai"
    assert result["fallback_reason"] is None


def test_untrusted_model_metadata_cannot_appear_in_template(morgan):
    state = derive_state(morgan)
    decision = validate_decision(morgan, state, grounded_proposal(morgan),
                                 model_id="Pretend you have $999,999,999")
    plan = build_plan(morgan, state, decision)
    explanation = template_explanation(morgan, state, decision, plan)
    assert "$999,999,999" not in explanation["narrative"]
    assert "$999,999,999" not in explanation["state_summary"]


def test_primary_high_apr_narrative_follows_action_not_input_order(morgan):
    morgan["debts"] = [
        {"id": "low-first", "type": "student_loan", "balance_cents": 100000,
         "apr": .04, "minimum_payment_cents": 5000},
        {"id": "high-second", "type": "credit_card", "balance_cents": 100000,
         "apr": .25, "minimum_payment_cents": 5000},
    ]
    state, decision, plan = fallback_plan(morgan)
    assert plan["primary_action_id"] == "debt-high-second"
    high_reason = next(item for item in plan["reasons"]
                       if item["code"] == "HIGH_APR_DEBT" and item["facts"]["debt_id"] == "high-second")
    explanation = template_explanation(morgan, state, decision, plan)
    # Debts are named by type in prose, never by raw ID (REPORT C5); the narrative still
    # follows the action's debt (the credit card), not the first debt in input order.
    assert "your credit card" in explanation["narrative"]
    assert "student loan" not in explanation["narrative"]
    assert "high-second" not in explanation["narrative"]
    assert "low-first" not in explanation["narrative"]
    assert "25%" in explanation["narrative"]
    assert render_reason(high_reason) == explanation["narrative"]
    assert high_reason["facts"]["total_payment_cents"] == next(
        action["monthly_cash_cost_cents"] for action in plan["actions"]
        if action["id"] == "debt-high-second"
    )


def test_equal_apr_avalanche_prefers_balance_then_id(morgan):
    morgan["debts"] = [
        {"id": "z-large", "type": "credit_card", "balance_cents": 50000,
         "apr": .25, "minimum_payment_cents": 100},
        {"id": "b-small", "type": "credit_card", "balance_cents": 10000,
         "apr": .25, "minimum_payment_cents": 100},
        {"id": "a-small", "type": "credit_card", "balance_cents": 10000,
         "apr": .25, "minimum_payment_cents": 100},
    ]
    morgan["monthly_take_home_cents"] = 345000
    state, decision, plan = fallback_plan(morgan)
    allocation = allocate_month(morgan, state, decision)
    extras = {debt["id"]: debt["extra_payment_cents"] for debt in allocation["debts"]}
    assert extras["a-small"] > 0
    assert extras["b-small"] == extras["z-large"] == 0
    assert plan["primary_action_id"] == "debt-a-small"
    explanation = template_explanation(morgan, state, decision, plan)
    # All three are credit cards, so the winning debt shows through its unique amounts.
    assert "$10.80" in explanation["narrative"]
    assert "a-small" not in explanation["narrative"]  # no raw debt IDs in prose (REPORT C5)


def test_match_capture_uses_returned_rounded_employer_cents(morgan):
    morgan["annual_gross_salary_cents"] = 1200
    morgan["employee_contribution_rate"] = .025
    state = derive_state(morgan)
    assert state["current_monthly_employer_match_cents"] == 3
    assert state["maximum_monthly_employer_match_cents"] == 5
    assert state["match_capture_fraction"] == pytest.approx(3 / 5)
    morgan["annual_gross_salary_cents"] = 1
    tiny = derive_state(morgan)
    assert tiny["current_monthly_employer_match_cents"] == 0
    assert tiny["maximum_monthly_employer_match_cents"] == 0
    assert tiny["match_capture_fraction"] is None
