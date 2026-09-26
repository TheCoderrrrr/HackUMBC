"""TEMPORARY placeholder engine owned by Developer A.

It exists only so the API, AI pipeline and contract examples run end to end before
Developer B (state/policy) and Developer C (simulation/evaluate) land their modules.
Delete it once `engine_port` imports the real engine.

It computes the BACKEND.md section 6/7 opening-month state so the Recommendation
Agent sees realistic indicators, but it does NOT run the waterfall or simulation:
plans are a single information action and projections use the blocked shape, and
every evaluation carries a STUB_ENGINE warning.
"""
from __future__ import annotations

import hashlib
import json
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

from app.schemas import (
    SCHEMA_VERSION,
    AIExplanation,
    Change,
    ConstraintCheck,
    DecisionSummary,
    EvaluationCore,
    FinancialProfile,
    FinancialState,
    GlidePathAnchor,
    ModelAssumptions,
    Plan,
    Projection,
    Projections,
    Rationale,
    RecommendationAction,
    RecommendationProposal,
    Scenario,
)

MODEL_VERSION = "1.0.0"
POLICY_VERSION = "1.0.0"
STUB_WARNING = "STUB_ENGINE: placeholder engine; plan and projections are not computed yet."

PRIORITIES = ("starter_reserve", "high_apr_debt", "full_reserve")
DEFAULT_ORDER = {
    "balanced": ["starter_reserve", "high_apr_debt", "full_reserve"],
    "cash_security": ["starter_reserve", "full_reserve", "high_apr_debt"],
    "debt_reduction": ["high_apr_debt", "starter_reserve", "full_reserve"],
}
# The one documented non-default ordering (BACKEND.md section 12).
ORDER_EXCEPTIONS = {"morgan-cash-security": ["starter_reserve", "high_apr_debt", "full_reserve"]}

GLIDE = [(30, 0.90), (20, 0.80), (10, 0.65), (0, 0.50)]
HIGH_APR = Decimal("0.10")

_B_FIXTURES = Path(__file__).resolve().parent.parent / "fixtures" / "profiles.json"
_A_PLACEHOLDER = Path(__file__).resolve().parent / "stub_profiles.json"


def _cents(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def load_demo_profiles() -> list[FinancialProfile]:
    """Prefer Developer B's fixtures once they exist; fall back to the placeholder copy."""
    path = _B_FIXTURES if _B_FIXTURES.exists() else _A_PLACEHOLDER
    data = json.loads(path.read_text(encoding="utf-8"))
    items = data["profiles"] if isinstance(data, dict) else data  # B's file is a plain list
    return [FinancialProfile.model_validate(p) for p in items]


def _match_rate(profile: FinancialProfile, rate: Decimal) -> Decimal:
    total = Decimal(0)
    for t in profile.employer_match.tiers:
        lo, hi = Decimal(str(t.employee_rate_from)), Decimal(str(t.employee_rate_to))
        total += Decimal(str(t.match_per_employee_dollar)) * max(Decimal(0), min(rate, hi) - lo)
    return total


def _equity_weight(years: float) -> float:
    if years >= GLIDE[0][0]:
        return GLIDE[0][1]
    for (y1, w1), (y0, w0) in zip(GLIDE, GLIDE[1:]):
        if y0 <= years <= y1:
            return round(w0 + (w1 - w0) * (years - y0) / (y1 - y0), 6)
    return GLIDE[-1][1]


def derive_state(profile: FinancialProfile) -> FinancialState:
    salary = Decimal(profile.annual_gross_salary_cents) / 12
    rate = Decimal(str(profile.employee_contribution_rate))
    k = Decimal(1) if profile.contribution_tax_treatment == "roth" else 1 - Decimal(
        str(profile.estimated_marginal_income_tax_rate)
    )
    contribution = _cents(salary * rate)
    cash_cost = _cents(salary * rate * k)
    resources = profile.monthly_take_home_cents + cash_cost
    required = 0
    for d in profile.debts:
        if d.balance_cents > 0:
            due = Decimal(d.balance_cents) * (1 + Decimal(str(d.apr)) / 12)
            required += min(d.minimum_payment_cents, _cents(due))
    allocatable = resources - profile.monthly_living_expenses_cents - required
    expenses = profile.monthly_living_expenses_cents

    confirmed = profile.employer_match.status == "confirmed"
    full_rate = profile.employer_match.tiers[-1].employee_rate_to if confirmed else None
    current_match = _cents(salary * _match_rate(profile, rate)) if confirmed else None
    max_match = _cents(salary * _match_rate(profile, Decimal(str(full_rate)))) if confirmed else None
    positive = [d for d in profile.debts if d.balance_cents > 0]
    years = profile.retirement_age - profile.age

    return FinancialState(
        months_until_retirement=12 * years,
        gross_monthly_salary_cents=_cents(salary),
        current_employee_contribution_cents=contribution,
        current_employee_cash_cost_cents=cash_cost,
        monthly_resources_before_retirement_cents=resources,
        monthly_required_debt_payments_cents=required,
        monthly_allocatable_budget_cents=allocatable,
        current_monthly_surplus_cents=allocatable - cash_cost,
        emergency_months=round(profile.emergency_cash_cents / expenses, 4),
        critical_reserve_target_cents=min(100000, expenses),
        starter_reserve_target_cents=expenses,
        full_reserve_target_cents=3 * expenses,
        employee_rate_for_full_match=full_rate,
        current_monthly_employer_match_cents=current_match,
        maximum_monthly_employer_match_cents=max_match,
        match_capture_fraction=round(current_match / max_match, 4) if max_match else None,
        high_interest_debt_cents=sum(d.balance_cents for d in positive if Decimal(str(d.apr)) >= HIGH_APR),
        highest_debt_apr=max((d.apr for d in positive), default=None),
        baseline_equity_weight=_equity_weight(years),
        warnings=[STUB_WARNING],
    )


def blocking_issue(profile: FinancialProfile, state: FinancialState) -> str | None:
    if profile.employer_match.status == "unknown" or (
        profile.employer_match.status == "confirmed" and not profile.employer_match.fully_vested
    ):
        return "MISSING_REQUIRED_INPUT"
    if state.monthly_allocatable_budget_cents < 0:
        return "CASH_FLOW_SHORTFALL"
    return None


def default_order(preference: str) -> list[str]:
    return list(DEFAULT_ORDER[preference])


def permitted_orders(profile: FinancialProfile) -> list[list[str]]:
    orders = [default_order(profile.planning_preference)]
    extra = ORDER_EXCEPTIONS.get(profile.id)
    if extra and extra not in orders:
        orders.append(list(extra))
    return orders


def agent_indicators(profile: FinancialProfile, state: FinancialState) -> dict[str, float | int | None]:
    take_home = profile.monthly_take_home_cents
    return {
        "liquidity.emergency_months": state.emergency_months,
        "liquidity.starter_reserve_funded": profile.emergency_cash_cents >= state.starter_reserve_target_cents,
        "liquidity.full_reserve_funded": profile.emergency_cash_cents >= state.full_reserve_target_cents,
        "debt.high_interest_debt_cents": state.high_interest_debt_cents,
        "debt.highest_debt_apr": state.highest_debt_apr,
        "debt.burden_ratio": round(12 * state.monthly_required_debt_payments_cents / profile.annual_gross_salary_cents, 4),
        "capacity.monthly_surplus_cents": state.current_monthly_surplus_cents,
        "capacity.savings_ratio": round(state.current_monthly_surplus_cents / take_home, 4) if take_home else None,
        "match.capture_fraction": state.match_capture_fraction,
        "horizon.years_to_retirement": profile.retirement_age - profile.age,
    }


def _fallback_rationale(order: list[str]) -> list[Rationale]:
    text = {
        "starter_reserve": "Keep one month of expenses available before other priorities.",
        "high_apr_debt": "Direct extra cash to debt at 10% APR or more.",
        "full_reserve": "Build three months of expenses once earlier priorities are met.",
    }
    return [Rationale(priority=p, summary=text[p], evidence_paths=[], tradeoff="") for p in order]


def _check_proposal(profile, state, proposal: RecommendationProposal) -> str | None:
    order = proposal.ordered_priorities
    if sorted(order) != sorted(PRIORITIES) or len(order) != 3:
        return "priorities must be a permutation of starter_reserve, high_apr_debt, full_reserve"
    if order.index("starter_reserve") > order.index("full_reserve"):
        return "starter_reserve must precede full_reserve"
    if order not in permitted_orders(profile):
        return "order is not permitted for this profile"
    allowed_paths = set(agent_indicators(profile, state))
    by_priority = {r.priority: r for r in proposal.rationale}
    if set(by_priority) != set(PRIORITIES) or len(proposal.rationale) != 3:
        return "rationale must cover each priority exactly once"
    for r in proposal.rationale:
        if not r.summary.strip() or not r.tradeoff.strip():
            return "rationale summary and tradeoff must be populated"
        if not r.evidence_paths or not set(r.evidence_paths) <= allowed_paths:
            return "rationale cites unknown evidence paths"
    return None


def validate_decision(
    profile: FinancialProfile,
    state: FinancialState,
    proposal: RecommendationProposal | None,
    *,
    decision_id: str,
    prompt_version: str,
    fallback_reason: str | None = None,
) -> DecisionSummary:
    problem = _check_proposal(profile, state, proposal) if proposal else None
    accepted = proposal is not None and problem is None
    if accepted:
        order, rationale = list(proposal.ordered_priorities), proposal.rationale
    else:
        order = DEFAULT_ORDER[profile.planning_preference]
        rationale = _fallback_rationale(order)
    checks = [
        ConstraintCheck(code="PRIORITY_PERMUTATION", passed=True),
        ConstraintCheck(code="STARTER_BEFORE_FULL_RESERVE", passed=order.index("starter_reserve") < order.index("full_reserve")),
    ]
    return DecisionSummary(
        decision_id=decision_id,
        source="ai" if accepted else "rules_fallback",
        model_id=proposal.model_id if accepted else None,
        prompt_version=prompt_version,
        ordered_priorities=order,
        rationale=rationale,
        constraint_checks=checks,
        fallback_reason=None if accepted else (f"invalid_proposal: {problem}" if problem else fallback_reason),
    )


def _assumptions() -> ModelAssumptions:
    return ModelAssumptions(
        annual_equity_return=0.06, annual_bond_return=0.03, annual_cash_return=0.0,
        annual_inflation=0.025, annual_salary_growth=0.025, annual_living_cost_growth=0.025,
        annual_employee_limit_growth=0.025, high_interest_apr_threshold=0.10,
        retirement_total_saving_target=0.15, critical_reserve_cap_cents=100000,
        starter_reserve_months=1, full_reserve_months=3, returns_net_of_fees=True,
        glide_path=[GlidePathAnchor(years_to_retirement=y, equity_weight=w) for y, w in GLIDE],
        limitations=["Illustrative assumptions, not forecasts."],
    )


def _pending_projection(strategy: str, retirement_age: int) -> Projection:
    return Projection(
        strategy=strategy, retirement_age=retirement_age, feasible=False, shortfall_cents=None,
        retirement_balance_nominal_cents=None, retirement_balance_today_cents=None,
        cash_nominal_cents=None, debt_nominal_cents=None, cumulative_debt_interest_cents=None,
        debt_free_month=None, starter_reserve_month=None, full_reserve_month=None, points=[],
    )


def evaluate(profile: FinancialProfile, scenario: Scenario | None, decision: DecisionSummary) -> EvaluationCore:
    state = derive_state(profile)
    action = RecommendationAction(
        id="engine-pending", rank=1, category="cash_flow", status="information",
        monthly_cash_cost_cents=0, employee_contribution_cents=None, employee_contribution_rate=None,
        debt_id=None, target_balance_cents=None, reason_codes=[],
    )
    payload = json.dumps(
        {"profile": profile.model_dump(mode="json"), "scenario": scenario.model_dump(mode="json") if scenario else None,
         "order": decision.ordered_priorities, "model": decision.model_id, "prompt": decision.prompt_version},
        sort_keys=True, separators=(",", ":"),
    )
    return EvaluationCore(
        schema_version=SCHEMA_VERSION, model_version=MODEL_VERSION, policy_version=POLICY_VERSION,
        profile_id=profile.id, input_hash=hashlib.sha256(payload.encode()).hexdigest(),
        financial_state=state,
        plan=Plan(primary_action_id=action.id, actions=[action], reasons=[]),
        assumptions=_assumptions(),
        projections=Projections(
            current=_pending_projection("current", profile.retirement_age),
            adaptive=_pending_projection("adaptive", profile.retirement_age),
            custom=_pending_projection("custom", scenario.retirement_age) if scenario else None,
        ),
        warnings=[STUB_WARNING],
    )


def template_explanation(
    profile: FinancialProfile, core: EvaluationCore, decision: DecisionSummary, changes: list[Change]
) -> AIExplanation:
    labels = {"starter_reserve": "a starter emergency reserve", "high_apr_debt": "high-interest debt",
              "full_reserve": "a full emergency reserve"}
    order = ", then ".join(labels[p] for p in decision.ordered_priorities)
    return AIExplanation(
        state_summary="Your plan keeps the target-date allocation and focuses on your cash priorities.",
        narrative=f"After essentials and the employer match, extra cash goes to {order}.",
        source="template",
        changes=changes,
    )
