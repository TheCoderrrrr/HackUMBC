"""Deterministic, fact-grounded explanation fallback."""

from __future__ import annotations

from decimal import Decimal
from typing import Mapping


def _dollars(value: int) -> str:
    return f"${Decimal(value) / 100:,.2f}"


def _percent(value: float) -> str:
    return f"{value * 100:g}%"


def render_reason(reason: Mapping[str, object]) -> str:
    """Render a documented reason from its structured facts only."""
    code = reason["code"]
    facts = reason["facts"]
    if code == "CASH_FLOW_SHORTFALL":
        return (
            f"Living expenses and required debt payments exceed reconstructed monthly resources "
            f"by {_dollars(facts['shortfall_cents'])}."
        )
    if code == "MISSING_REQUIRED_INPUT":
        return "Confirm the employer matching terms and vesting before calculating a recommendation."
    if code == "CRITICAL_LIQUIDITY":
        text = (
            f"Add {_dollars(facts['cash_added_cents'])} toward the critical cash reserve "
            f"of {_dollars(facts['target_balance_cents'])}."
        )
        if facts["foregone_employer_match_cents"] > 0:
            text += (
                f" Funding this reserve temporarily forgoes "
                f"{_dollars(facts['foregone_employer_match_cents'])} of employer matching this month."
            )
        return text
    if code == "CAPTURE_EMPLOYER_MATCH":
        return (
            f"The {_dollars(facts['employee_contribution_cents'])} employee contribution "
            f"receives {_dollars(facts['employer_contribution_cents'])} of employer matching; "
            f"the full-match employee rate is {_percent(facts['required_employee_rate'])}."
        )
    if code == "MATCH_PARTIALLY_AFFORDABLE":
        return (
            f"The affordable employee contribution is {_dollars(facts['employee_contribution_cents'])}; "
            f"full matching requires an employee rate of {_percent(facts['required_employee_rate'])}."
        )
    if code == "BUILD_STARTER_RESERVE":
        return (
            f"Add {_dollars(facts['cash_added_cents'])} toward the one-month cash target "
            f"of {_dollars(facts['target_balance_cents'])}."
        )
    if code == "HIGH_APR_DEBT":
        return (
            f"Pay {_dollars(facts['total_payment_cents'])} on debt {facts['debt_id']} "
            f"at {_percent(facts['apr_rate'])} APR, including "
            f"{_dollars(facts['extra_payment_cents'])} beyond the "
            f"{_dollars(facts['minimum_payment_cents'])} required payment."
        )
    if code == "MAINTAIN_DEBT_MINIMUM":
        return (
            f"Pay the {_dollars(facts['total_payment_cents'])} required payment "
            f"on debt {facts['debt_id']}."
        )
    if code == "BUILD_FULL_RESERVE":
        return (
            f"Add {_dollars(facts['cash_added_cents'])} toward the three-month cash target "
            f"of {_dollars(facts['target_balance_cents'])}."
        )
    if code == "INCREASE_RETIREMENT_SAVING":
        return (
            f"Increase the employee contribution from "
            f"{_dollars(facts['original_employee_contribution_cents'])} to "
            f"{_dollars(facts['employee_contribution_cents'])} this month."
        )
    if code == "MAINTAIN_CONTRIBUTION":
        return (
            f"Maintain the {_percent(facts['employee_contribution_rate'])} employee election, "
            f"or {_dollars(facts['employee_contribution_cents'])} this month."
        )
    if code == "ADJUST_CONTRIBUTION":
        return (
            f"Set this month's affordable employee contribution to "
            f"{_dollars(facts['employee_contribution_cents'])}, from "
            f"{_dollars(facts['original_employee_contribution_cents'])} in the current election."
        )
    if code == "UNASSIGNED_SURPLUS":
        return f"Keep the remaining {_dollars(facts['cash_added_cents'])} as cash."
    if code == "BASELINE_ALLOCATION_RETAINED":
        return (
            f"The illustrative target-date allocation is {_percent(facts['equity_weight_rate'])} "
            f"equity and {_percent(facts['bond_weight_rate'])} bonds. "
            "No personal portfolio optimization was performed."
        )
    if code == "SIMPLIFIED_TAX_ESTIMATE":
        return (
            f"The {_dollars(facts['employee_contribution_cents'])} traditional contribution "
            f"has an estimated {_dollars(facts['employee_cash_cost_cents'])} take-home cost "
            f"using the supplied {_percent(facts['estimated_marginal_income_tax_rate'])} marginal rate."
        )
    raise ValueError(f"No template for reason code {code}")


def template_explanation(
    profile: Mapping[str, object], state: Mapping[str, object],
    decision: Mapping[str, object], plan: Mapping[str, object],
    changes: list[Mapping[str, object]] | None = None,
) -> dict[str, object]:
    """Describe the validated first-month plan without introducing new facts."""
    primary = next(
        action for action in plan["actions"]
        if action["id"] == plan["primary_action_id"]
    )
    primary_code = (
        "MAINTAIN_CONTRIBUTION"
        if primary["status"] == "maintain"
        and "MAINTAIN_CONTRIBUTION" in primary["reason_codes"]
        else next(code for code in primary["reason_codes"]
                  if code not in {"SIMPLIFIED_TAX_ESTIMATE", "BASELINE_ALLOCATION_RETAINED"})
    )
    primary_reason = next(
        reason for reason in plan["reasons"]
        if reason["code"] == primary_code
        and (primary["debt_id"] is None or reason["facts"].get("debt_id") == primary["debt_id"])
    )
    narrative = render_reason(primary_reason)
    if changes:
        narrative += " The recorded changes from the prior decision are listed with this evaluation."
    months = state["emergency_months"]
    month_word = "month" if months == 1 else "months"
    state_summary = (
        f"Monthly resources before retirement contributions are "
        f"{_dollars(state['monthly_resources_before_retirement_cents'])}; "
        f"required debt payments are {_dollars(state['monthly_required_debt_payments_cents'])}, "
        f"and emergency cash covers {months:g} {month_word} of living expenses."
    )
    return {
        "state_summary": state_summary,
        "narrative": narrative,
        "source": "template",
        "changes": [dict(change) for change in changes] if changes else [],
    }
