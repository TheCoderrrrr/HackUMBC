"""Bounded decision validation and the reusable adaptive monthly cash allocator.

Pass a fresh ``derive_state(profile)`` result with each monthly profile. Simulations may
update salary, living costs, cap, debts, and cash before deriving that month's state.
No function here mutates the profile, state, or decision.
"""

from __future__ import annotations

import secrets
import re
from copy import deepcopy
from decimal import Decimal, ROUND_FLOOR
from typing import Mapping

from .assumptions import MODEL_ASSUMPTIONS
from .money import (
    cents, contribution_cash_cost_cents, decimal, employee_contribution_cents,
    employer_match_cents, full_match_employee_rate, match_rate, monthly_debt_interest_cents,
    monthly_gross_cents,
)
from .state import derive_state, recommendation_context

PRIORITIES = ("starter_reserve", "high_apr_debt", "full_reserve")
PREFERENCE_ORDER = {
    "balanced": ("starter_reserve", "high_apr_debt", "full_reserve"),
    "cash_security": ("starter_reserve", "full_reserve", "high_apr_debt"),
    "debt_reduction": ("high_apr_debt", "starter_reserve", "full_reserve"),
}


def default_priorities(preference: str) -> tuple[str, str, str]:
    return PREFERENCE_ORDER[preference]


def _is_morgan_exception(profile: Mapping[str, object]) -> bool:
    """Pin the one allowed AI variation to the documented synthetic financial facts."""
    debts = profile["debts"]
    match = profile["employer_match"]
    return (
        profile.get("source") == "demo"
        and profile.get("planning_preference") == "cash_security"
        and profile["age"] == 35
        and profile["retirement_age"] == 67
        and profile["annual_gross_salary_cents"] == 8_400_000
        and profile["monthly_take_home_cents"] == 480_000
        and profile["monthly_living_expenses_cents"] == 360_000
        and decimal(profile["employee_contribution_rate"]) == Decimal("0.08")
        and profile["emergency_cash_cents"] == 360_000
        and profile["contribution_tax_treatment"] == "traditional"
        and decimal(profile["estimated_marginal_income_tax_rate"]) == Decimal("0.22")
        and profile["annual_employee_limit_cents"] == 2_450_000
        and profile["retirement_balance_cents"] == 3_500_000
        and match["status"] == "confirmed"
        and match["fully_vested"] is True
        and len(match["tiers"]) == 1
        and decimal(match["tiers"][0]["employee_rate_from"]) == 0
        and decimal(match["tiers"][0]["employee_rate_to"]) == Decimal("0.05")
        and decimal(match["tiers"][0]["match_per_employee_dollar"]) == 1
        and len(debts) == 1
        and debts[0]["type"] == "credit_card"
        and debts[0]["balance_cents"] == 1_800_000
        and decimal(debts[0]["apr"]) == Decimal("0.25")
        and debts[0]["minimum_payment_cents"] == 40_000
    )


def _valid_order(
    profile: Mapping[str, object], order: object, allow_morgan_exception: bool
) -> bool:
    if not isinstance(order, (list, tuple)) or len(order) != 3 or not all(isinstance(x, str) for x in order):
        return False
    if set(order) != set(PRIORITIES) or order.index("starter_reserve") > order.index("full_reserve"):
        return False
    default = default_priorities(profile.get("planning_preference", "balanced"))
    return tuple(order) == default or (
        allow_morgan_exception and _is_morgan_exception(profile)
        and tuple(order) == PRIORITIES
    )


def _evidence_values(profile: Mapping[str, object], state: Mapping[str, object]) -> dict[str, object]:
    context = recommendation_context(profile, state)
    values = {key: value for key, value in context.items() if key != "financial_state"}
    values.update({f"financial_state.{key}": value for key, value in context["financial_state"].items()})
    return values


_NUMERIC_PROSE = re.compile(r"[\d$€£%]|\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion)(?:[\s-]+[a-z]+){0,3}[\s-]+(?:dollars?|cents?|percent(?:age)?(?: points?)?)\b", re.IGNORECASE)
_UNSUPPORTED_CLAIM = re.compile(
    r"\b(?:guarantee(?:d|s)?|certain(?:ly)?|assured?|risk[ -]?free|"
    r"ready for retirement|retirement readiness|retire comfortably|"
    r"success probability|probability of success|chance of success|"
    r"will retire|will be enough|cannot lose|"
    r"age|aged|years old|young(?:er)?|older|senior|"
    r"millennial|gen[ -]?z|boomer|generation|personality|"
    r"risk[ -]?averse|risk[ -]?toleran(?:ce|t)|cautious person|"
    r"conservative (?:person|investor)|aggressive (?:person|investor))\b",
    re.IGNORECASE,
)


def _unsupported_rationale_claim(text: str, profile: Mapping[str, object]) -> bool:
    """Provider prose must be qualitative; Python owns amounts and personal facts."""
    if _NUMERIC_PROSE.search(text) or _UNSUPPORTED_CLAIM.search(text):
        return True
    return any(
        re.search(rf"\b{re.escape(value)}\b", text, re.IGNORECASE)
        for value in (profile["name"], profile["id"])
        if value
    )


def _fallback_rationale(order: tuple[str, str, str]) -> list[dict[str, object]]:
    details = {
        "starter_reserve": (
            "Build cash toward one month of living expenses when needed.",
            ["financial_state.emergency_months", "financial_state.starter_reserve_target_cents"],
            "Cash held for emergencies is unavailable for extra debt or retirement contributions this month.",
        ),
        "high_apr_debt": (
            "Apply available extra cash to qualifying high-interest debt.",
            ["financial_state.high_interest_debt_cents", "financial_state.highest_debt_apr"],
            "Extra debt payments may delay reserve growth.",
        ),
        "full_reserve": (
            "Build cash toward the three-month reserve target when needed.",
            ["financial_state.emergency_months", "financial_state.full_reserve_target_cents"],
            "Additional reserves may delay high-interest debt repayment.",
        ),
    }
    return [
        {"priority": key, "summary": details[key][0],
         "evidence_paths": details[key][1], "tradeoff": details[key][2]}
        for key in order
    ]


def _proposal_problem(
    profile: Mapping[str, object], state: Mapping[str, object], proposal: object,
    allow_morgan_exception: bool,
) -> str | None:
    if not isinstance(proposal, Mapping) or set(proposal) != {"ordered_priorities", "rationale"}:
        return "INVALID_PROPOSAL_FIELDS"
    order = proposal["ordered_priorities"]
    if not _valid_order(profile, order, allow_morgan_exception):
        return "INVALID_PRIORITY_ORDER"
    rationale = proposal["rationale"]
    if not isinstance(rationale, list) or len(rationale) != 3:
        return "INVALID_RATIONALE"
    values = _evidence_values(profile, state)
    for position, item in enumerate(rationale):
        if not isinstance(item, Mapping) or set(item) != {"priority", "summary", "evidence_paths", "tradeoff"}:
            return "INVALID_RATIONALE"
        if item["priority"] != order[position]:
            return "INVALID_RATIONALE"
        if not all(isinstance(item[key], str) and item[key].strip() for key in ("summary", "tradeoff")):
            return "INVALID_RATIONALE"
        paths = item["evidence_paths"]
        if not isinstance(paths, list) or not paths or not all(isinstance(path, str) for path in paths):
            return "INVALID_EVIDENCE"
        if len(paths) != len(set(paths)):
            return "INVALID_EVIDENCE"
        if any(path not in values or values[path] is None for path in paths):
            return "INVALID_EVIDENCE"
        if any(_unsupported_rationale_claim(item[key], profile) for key in ("summary", "tradeoff")):
            return "UNSUPPORTED_RATIONALE_CLAIM"
    return None


def validate_decision(
    profile: Mapping[str, object], state: Mapping[str, object], proposal: object,
    *, model_id: str | None = None, prompt_version: str = "1",
    allow_morgan_exception: bool = False,
) -> dict[str, object]:
    """Accept only a supported recommendation, otherwise return a rules decision.

    ``model_id`` and ``prompt_version`` are trusted orchestration metadata. A model
    cannot supply source, constraint checks, money, assumptions, or identifiers.
    """
    canonical = derive_state(profile)
    if dict(state) != canonical:
        raise ValueError("Financial state does not match the current profile")
    blocked = "MISSING_REQUIRED_INPUT" in state["warnings"] or "CASH_FLOW_SHORTFALL" in state["warnings"]
    problem = "BLOCKED_FINANCIAL_INPUT" if blocked else (
        "NO_AI_PROPOSAL" if proposal is None else
        "MISSING_MODEL_ID" if not isinstance(model_id, str) or not model_id.strip() else
        _proposal_problem(profile, state, proposal, allow_morgan_exception)
    )
    accepted = problem is None
    order = tuple(proposal["ordered_priorities"]) if accepted else default_priorities(
        profile.get("planning_preference", "balanced")
    )
    checks = [
        {"code": "EXACT_PRIORITY_MEMBERSHIP", "passed": set(order) == set(PRIORITIES)},
        {"code": "STARTER_BEFORE_FULL_RESERVE", "passed": order.index("starter_reserve") < order.index("full_reserve")},
        {"code": "SUPPORTED_PREFERENCE_ORDER", "passed": _valid_order(profile, order, allow_morgan_exception)},
        {"code": "EVIDENCE_VALIDATED", "passed": accepted or proposal is None or blocked},
        {"code": "ESSENTIALS_AND_MATCH_PROTECTED", "passed": True},
    ]
    return {
        "decision_id": secrets.token_urlsafe(24),
        "source": "ai" if accepted else "rules_fallback",
        "model_id": model_id if accepted else None,
        "prompt_version": prompt_version,
        "ordered_priorities": list(order),
        "rationale": deepcopy(proposal["rationale"]) if accepted else _fallback_rationale(order),
        "constraint_checks": checks,
        "fallback_reason": None if accepted else problem,
    }


def _employer_for_employee_cents(
    employee_cents: int, gross: Decimal, match: Mapping[str, object]
) -> int:
    return employer_match_cents(gross, decimal(employee_cents) / gross, match)


def _max_affordable_employee_cents(
    ceiling: int, available_cash_cents: int, tax_treatment: str, tax_rate: object
) -> int:
    low, high = 0, max(0, ceiling)
    while low < high:
        midpoint = (low + high + 1) // 2
        if contribution_cash_cost_cents(midpoint, tax_treatment, tax_rate) <= available_cash_cents:
            low = midpoint
        else:
            high = midpoint - 1
    return low


def _target_employee_cents(gross: Decimal, match: Mapping[str, object]) -> int:
    """Find minimum employee cents meeting the 15% combined heuristic."""
    target = cents(gross * decimal(MODEL_ASSUMPTIONS["retirement_total_saving_target"]))
    low, high = 0, cents(gross)
    while low < high:
        midpoint = (low + high) // 2
        if midpoint + _employer_for_employee_cents(midpoint, gross, match) >= target:
            high = midpoint
        else:
            low = midpoint + 1
    return low


MONTH_KEYS = frozenset({
    "annual_gross_salary_cents", "monthly_resources_before_retirement_cents",
    "monthly_living_expenses_cents", "annual_employee_limit_cents",
    "emergency_cash_cents", "debts",
})


def _month_snapshot(
    profile: Mapping[str, object], state: Mapping[str, object], month: Mapping[str, object] | None,
) -> dict[str, object]:
    """Validate a simulator snapshot with fixed original debt IDs and terms.

    Debt balances may change; type, APR, and entered minimum stay fixed nominal,
    including for paid-off debts retained with a zero opening balance.
    """
    if month is None:
        return {
            "annual_gross_salary_cents": profile["annual_gross_salary_cents"],
            "monthly_resources_before_retirement_cents": state["monthly_resources_before_retirement_cents"],
            "monthly_living_expenses_cents": profile["monthly_living_expenses_cents"],
            "annual_employee_limit_cents": profile["annual_employee_limit_cents"],
            "emergency_cash_cents": profile["emergency_cash_cents"],
            "debts": profile["debts"],
        }
    if not isinstance(month, Mapping) or set(month) != MONTH_KEYS:
        raise ValueError("month must contain exactly the documented snapshot fields")
    for key in MONTH_KEYS - {"debts"}:
        value = month[key]
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"month.{key} must be an integer number of cents")
        minimum = 1 if key in {"annual_gross_salary_cents", "monthly_living_expenses_cents"} else 0
        if value < minimum:
            raise ValueError(f"month.{key} is outside the supported range")
    debts = month["debts"]
    if not isinstance(debts, list) or len(debts) > 20:
        raise ValueError("month.debts must be an array of at most 20 debts")
    original_debts = {debt["id"]: debt for debt in profile["debts"]}
    if len(debts) != len(original_debts):
        raise ValueError("month.debts must retain every original debt")
    seen: set[str] = set()
    for index, debt in enumerate(debts):
        path = f"month.debts.{index}"
        if not isinstance(debt, Mapping) or set(debt) != {
            "id", "type", "balance_cents", "apr", "minimum_payment_cents"
        }:
            raise ValueError(f"{path} must contain exactly the canonical debt fields")
        debt_id = debt["id"]
        if not isinstance(debt_id, str) or not debt_id.strip() or debt_id in seen:
            raise ValueError(f"{path}.id must be nonempty and unique")
        seen.add(debt_id)
        original_debt = original_debts.get(debt_id)
        if original_debt is None:
            raise ValueError(f"{path}.id is not an original debt")
        if debt["type"] not in {"credit_card", "student_loan", "other"}:
            raise ValueError(f"{path}.type is unsupported")
        if debt["type"] != original_debt["type"]:
            raise ValueError(f"{path}.type cannot change from the original debt")
        for key in ("balance_cents", "minimum_payment_cents"):
            value = debt[key]
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                raise ValueError(f"{path}.{key} must be a nonnegative integer")
        if debt["balance_cents"] > 0 and debt["minimum_payment_cents"] == 0:
            raise ValueError(f"{path}.minimum_payment_cents is required for positive debt")
        if isinstance(debt["apr"], (bool, str)):
            raise ValueError(f"{path}.apr must be a finite rate")
        try:
            apr = decimal(debt["apr"])
        except ValueError as exc:
            raise ValueError(f"{path}.apr must be a finite rate") from exc
        if not 0 <= apr <= 1:
            raise ValueError(f"{path}.apr is outside the supported range")
        if apr != decimal(original_debt["apr"]):
            raise ValueError(f"{path}.apr cannot change from the original debt")
        if debt["minimum_payment_cents"] != original_debt["minimum_payment_cents"]:
            raise ValueError(f"{path}.minimum_payment_cents cannot change from the original debt")
    return dict(month)


def allocate_month(
    profile: Mapping[str, object], state: Mapping[str, object], decision: Mapping[str, object],
    *, month: Mapping[str, object] | None = None, strategy: str = "adaptive",
    employee_contribution_rate: float | None = None,
    allow_morgan_exception: bool = False,
) -> dict[str, object]:
    """Allocate a modeled month under adaptive, current, or custom strategy.

    ``profile`` and ``state`` must be the original canonical pair. ``month`` is a
    trusted Python-generated snapshot with exactly ``MONTH_KEYS``; when omitted,
    the original profile's opening month is used. Snapshot cash and debts are
    opening balances. The original election, tax treatment, match, and decision
    remain fixed while salary, resources, expenses, cap, cash, and debts evolve.
    A custom fixed election is checked against the original cap when ``month``
    is omitted, then limited by each modeled month's cap. Existing cash is
    considered for reserve gaps but never liquidated for debt.
    """
    canonical = derive_state(profile)
    if dict(state) != canonical:
        raise ValueError("Financial state does not match the current profile")
    if not isinstance(decision, Mapping) or not _valid_order(
        profile, decision.get("ordered_priorities"), allow_morgan_exception
    ):
        raise ValueError("Unsupported decision order")
    if strategy not in {"adaptive", "current", "custom"}:
        raise ValueError("Unsupported strategy")
    if strategy != "custom" and employee_contribution_rate is not None:
        raise ValueError("Contribution override is only supported for custom strategy")
    fixed_rate = None
    if strategy == "current":
        fixed_rate = decimal(profile["employee_contribution_rate"])
    elif strategy == "custom" and employee_contribution_rate is not None:
        if isinstance(employee_contribution_rate, (bool, str)):
            raise ValueError("Custom employee contribution rate must be a finite number")
        try:
            fixed_rate = decimal(employee_contribution_rate)
        except ValueError as exc:
            raise ValueError("Custom employee contribution rate must be a finite number") from exc
        if not 0 <= fixed_rate <= 1:
            raise ValueError("Custom employee contribution rate must be between 0 and 1")
        if month is None and decimal(profile["annual_gross_salary_cents"]) * fixed_rate > profile["annual_employee_limit_cents"]:
            raise ValueError("Custom employee contribution rate exceeds the original annual employee cap")
    snapshot = _month_snapshot(profile, state, month)
    gross = monthly_gross_cents(snapshot["annual_gross_salary_cents"])
    resources = snapshot["monthly_resources_before_retirement_cents"]
    living = snapshot["monthly_living_expenses_cents"]
    debts = []
    for debt in snapshot["debts"]:
        interest = monthly_debt_interest_cents(debt["balance_cents"], debt["apr"])
        due = debt["balance_cents"] + interest
        minimum = min(debt["minimum_payment_cents"], due)
        debts.append({
            "id": debt["id"], "type": debt["type"], "apr": debt["apr"],
            "opening_balance_cents": debt["balance_cents"], "interest_cents": interest,
            "amount_due_cents": due, "minimum_payment_cents": minimum,
            "extra_payment_cents": 0, "total_payment_cents": minimum,
            "closing_balance_cents": due - minimum,
        })
    required = sum(debt["minimum_payment_cents"] for debt in debts)
    if month is None and required != state["monthly_required_debt_payments_cents"]:
        raise ValueError("Capped debt minimums do not match financial state")
    shortfall = max(0, living + required - resources)
    blocked_match = "MISSING_REQUIRED_INPUT" in state["warnings"]
    month_warnings = [warning for warning in state["warnings"] if warning != "CASH_FLOW_SHORTFALL"]
    if shortfall:
        month_warnings.append("CASH_FLOW_SHORTFALL")
    result = {
        "strategy": strategy,
        "feasible": shortfall == 0 and not blocked_match,
        "shortfall_cents": shortfall if shortfall else None,
        "resources_cents": resources,
        "living_expenses_cents": living,
        "required_debt_payments_cents": required,
        "employee_contribution_cents": 0,
        "employee_contribution_rate": 0.0,
        "employee_cash_cost_cents": 0,
        "employer_match_cents": None if blocked_match else 0,
        "debts": debts,
        "cash_to_critical_reserve_cents": 0,
        "critical_reserve_match_forgone_cents": 0,
        "cash_to_starter_reserve_cents": 0,
        "cash_to_full_reserve_cents": 0,
        "residual_cash_cents": 0,
        "total_cash_added_cents": 0,
        "warnings": month_warnings,
    }
    if not result["feasible"]:
        for debt in debts:
            debt["total_payment_cents"] = 0
            debt["closing_balance_cents"] = debt["opening_balance_cents"]
        return result

    available = resources - living - required
    cash_total = snapshot["emergency_cash_cents"]
    tax = profile["estimated_marginal_income_tax_rate"]
    treatment = profile["contribution_tax_treatment"]
    annual_cap = snapshot["annual_employee_limit_cents"]
    monthly_cap = int((decimal(annual_cap) / 12).to_integral_value(rounding=ROUND_FLOOR))
    salary_ceiling = int(gross.to_integral_value(rounding=ROUND_FLOOR))
    ceiling = min(monthly_cap, salary_ceiling)
    match = profile["employer_match"]
    critical_target = min(MODEL_ASSUMPTIONS["critical_reserve_cap_cents"], living)
    starter_target = living * MODEL_ASSUMPTIONS["starter_reserve_months"]
    full_target = living * MODEL_ASSUMPTIONS["full_reserve_months"]

    def fund_reserve(target: int, key: str) -> None:
        nonlocal available, cash_total
        amount = min(available, max(0, target - cash_total))
        result[key] += amount
        available -= amount
        cash_total += amount

    def add_contribution(target: int) -> None:
        nonlocal available
        current = result["employee_contribution_cents"]
        affordable = _max_affordable_employee_cents(
            min(target, ceiling), available + result["employee_cash_cost_cents"], treatment, tax
        )
        employee = max(current, affordable)
        cost = contribution_cash_cost_cents(employee, treatment, tax)
        available -= cost - result["employee_cash_cost_cents"]
        result["employee_contribution_cents"] = employee
        result["employee_cash_cost_cents"] = cost
        result["employee_contribution_rate"] = float(decimal(employee) / gross)
        result["employer_match_cents"] = _employer_for_employee_cents(employee, gross, match)

    def spend_priorities() -> None:
        nonlocal available
        for priority in decision["ordered_priorities"]:
            if priority == "starter_reserve":
                fund_reserve(starter_target, "cash_to_starter_reserve_cents")
            elif priority == "full_reserve":
                fund_reserve(full_target, "cash_to_full_reserve_cents")
            else:
                candidates = sorted(
                    (debt for debt in debts if debt["opening_balance_cents"] > 0
                     and decimal(debt["apr"]) >= decimal(MODEL_ASSUMPTIONS["high_interest_apr_threshold"])),
                    key=lambda debt: (-decimal(debt["apr"]), debt["opening_balance_cents"], debt["id"]),
                )
                for debt in candidates:
                    extra = min(available, debt["amount_due_cents"] - debt["minimum_payment_cents"])
                    debt["extra_payment_cents"] = extra
                    debt["total_payment_cents"] += extra
                    debt["closing_balance_cents"] -= extra
                    available -= extra

    if fixed_rate is not None:
        employee = min(employee_contribution_cents(gross, fixed_rate), ceiling)
        cost = contribution_cash_cost_cents(employee, treatment, tax)
        if cost > available:
            result["feasible"] = False
            result["shortfall_cents"] = cost - available
            result["warnings"].append(
                "INFEASIBLE_SCENARIO" if strategy == "custom" else "CURRENT_ELECTION_UNAFFORDABLE"
            )
            for debt in debts:
                debt["total_payment_cents"] = 0
                debt["closing_balance_cents"] = debt["opening_balance_cents"]
            return result
        result["employee_contribution_cents"] = employee
        result["employee_cash_cost_cents"] = cost
        result["employee_contribution_rate"] = float(decimal(employee) / gross)
        result["employer_match_cents"] = _employer_for_employee_cents(employee, gross, match)
        available -= cost
        if strategy == "custom":
            fund_reserve(critical_target, "cash_to_critical_reserve_cents")
            spend_priorities()
            if cash_total < full_target:
                result["warnings"].append("CUSTOM_LIQUIDITY_DELAYED")
    else:
        fund_reserve(critical_target, "cash_to_critical_reserve_cents")
        full_rate = full_match_employee_rate(match)
        full_match_cents = employee_contribution_cents(gross, full_rate)
        add_contribution(full_match_cents)
        if full_match_cents > 0 and result["employee_contribution_cents"] < full_match_cents:
            result["warnings"].append("MATCH_PARTIALLY_AFFORDABLE")
        spend_priorities()
        desired = max(
            _target_employee_cents(gross, match),
            employee_contribution_cents(gross, profile["employee_contribution_rate"]),
        )
        add_contribution(desired)
        if result["cash_to_critical_reserve_cents"] and full_match_cents:
            without_critical = _max_affordable_employee_cents(
                min(full_match_cents, ceiling), resources - living - required,
                treatment, tax,
            )
            potential_match = _employer_for_employee_cents(without_critical, gross, match)
            result["critical_reserve_match_forgone_cents"] = max(
                0, potential_match - result["employer_match_cents"]
            )
    result["residual_cash_cents"] = available
    result["total_cash_added_cents"] = (
        result["cash_to_critical_reserve_cents"] + result["cash_to_starter_reserve_cents"]
        + result["cash_to_full_reserve_cents"] + available
    )
    if available:
        result["warnings"].append("UNASSIGNED_SURPLUS")
    if any(debt["total_payment_cents"] < debt["interest_cents"] for debt in debts):
        result["warnings"].append("NEGATIVE_AMORTIZATION")
    if resources != living + sum(debt["total_payment_cents"] for debt in debts) + result["employee_cash_cost_cents"] + result["total_cash_added_cents"]:
        raise AssertionError("Monthly cash conservation failed")
    return result


def build_plan(
    profile: Mapping[str, object], state: Mapping[str, object], decision: Mapping[str, object],
    *, allow_morgan_exception: bool = False,
) -> dict[str, object]:
    """Express the first adaptive month as public actions and grounded reasons."""
    allocation = allocate_month(
        profile, state, decision, allow_morgan_exception=allow_morgan_exception
    )
    actions: list[dict[str, object]] = []
    reasons: list[dict[str, object]] = []

    def reason(
        code: str, facts: Mapping[str, object], input_paths: list[str]
    ) -> str:
        reasons.append({
            "code": code, "template_key": code.lower(),
            "facts": dict(facts), "input_paths": input_paths,
        })
        return code

    def action(
        action_id: str, category: str, status: str, cash_cost: int,
        reason_codes: list[str], *, employee: int | None = None,
        rate: float | None = None, debt_id: str | None = None,
        target: int | None = None,
    ) -> None:
        actions.append({
            "id": action_id, "rank": len(actions) + 1, "category": category,
            "status": status, "monthly_cash_cost_cents": cash_cost,
            "employee_contribution_cents": employee,
            "employee_contribution_rate": rate,
            "debt_id": debt_id, "target_balance_cents": target,
            "reason_codes": list(dict.fromkeys(reason_codes)),
        })

    if not allocation["feasible"]:
        if allocation["shortfall_cents"]:
            code = reason("CASH_FLOW_SHORTFALL", {
                "resources_cents": allocation["resources_cents"],
                "living_expenses_cents": allocation["living_expenses_cents"],
                "required_debt_payments_cents": allocation["required_debt_payments_cents"],
                "shortfall_cents": allocation["shortfall_cents"],
            }, ["monthly_take_home_cents", "employee_contribution_rate",
                "monthly_living_expenses_cents", "debts"])
            action("cash-flow-shortfall", "cash_flow", "blocked", 0, [code])
        if "MISSING_REQUIRED_INPUT" in allocation["warnings"]:
            code = reason("MISSING_REQUIRED_INPUT", {
                "match_status": profile["employer_match"]["status"],
                "fully_vested": profile["employer_match"]["fully_vested"],
            }, ["employer_match.status", "employer_match.fully_vested"])
            action("missing-match-input", "cash_flow", "blocked", 0, [code])
        return {"primary_action_id": actions[0]["id"], "actions": actions, "reasons": reasons}

    employee = allocation["employee_contribution_cents"]
    original = state["current_employee_contribution_cents"]
    match_threshold = state["employee_rate_for_full_match"]
    full_match_employee = employee_contribution_cents(
        monthly_gross_cents(profile["annual_gross_salary_cents"]), match_threshold
    )
    contribution_codes: list[str] = []
    match_facts = {
        "employee_contribution_cents": employee,
        "employer_contribution_cents": allocation["employer_match_cents"],
        "required_employee_rate": match_threshold,
        "original_employee_contribution_cents": original,
        "actual_employee_rate": allocation["employee_contribution_rate"],
    }
    match_paths = ["annual_gross_salary_cents", "employee_contribution_rate",
                   "employer_match.status", "employer_match.tiers"]
    if "MATCH_PARTIALLY_AFFORDABLE" in allocation["warnings"]:
        contribution_codes.append(reason("MATCH_PARTIALLY_AFFORDABLE", match_facts, match_paths))
    elif profile["employer_match"]["status"] == "confirmed" and employee >= full_match_employee:
        contribution_codes.append(reason("CAPTURE_EMPLOYER_MATCH", match_facts, match_paths))
    if employee > original:
        contribution_codes.append(reason("INCREASE_RETIREMENT_SAVING", {
            "original_employee_contribution_cents": original,
            "employee_contribution_cents": employee,
            "employer_contribution_cents": allocation["employer_match_cents"],
            "combined_saving_target_rate": MODEL_ASSUMPTIONS["retirement_total_saving_target"],
        }, ["employee_contribution_rate", "annual_gross_salary_cents", "employer_match.tiers"]))
    elif employee == original:
        contribution_codes.append(reason("MAINTAIN_CONTRIBUTION", {
            "employee_contribution_cents": employee,
            "employee_contribution_rate": allocation["employee_contribution_rate"],
        }, ["employee_contribution_rate", "annual_gross_salary_cents"]))
    elif not contribution_codes:
        contribution_codes.append(reason("ADJUST_CONTRIBUTION", {
            "original_employee_contribution_cents": original,
            "employee_contribution_cents": employee,
        }, ["employee_contribution_rate", "monthly_take_home_cents",
            "monthly_living_expenses_cents", "debts"]))
    if profile["contribution_tax_treatment"] == "traditional":
        contribution_codes.append(reason("SIMPLIFIED_TAX_ESTIMATE", {
            "employee_contribution_cents": employee,
            "employee_cash_cost_cents": allocation["employee_cash_cost_cents"],
            "estimated_marginal_income_tax_rate": profile["estimated_marginal_income_tax_rate"],
        }, ["contribution_tax_treatment", "estimated_marginal_income_tax_rate"]))
    action("employee-contribution", "contribution",
           "maintain" if employee == original else "action",
           allocation["employee_cash_cost_cents"], contribution_codes,
           employee=employee, rate=allocation["employee_contribution_rate"])

    reserve_specs = (
        ("critical", "CRITICAL_LIQUIDITY", "cash_to_critical_reserve_cents", "critical_reserve_target_cents"),
        ("starter", "BUILD_STARTER_RESERVE", "cash_to_starter_reserve_cents", "starter_reserve_target_cents"),
        ("full", "BUILD_FULL_RESERVE", "cash_to_full_reserve_cents", "full_reserve_target_cents"),
    )
    for label, code, amount_key, target_key in reserve_specs:
        amount = allocation[amount_key]
        if amount:
            reserve_facts = {
                "starting_cash_cents": profile["emergency_cash_cents"],
                "cash_added_cents": amount,
                "target_balance_cents": state[target_key],
            }
            reserve_paths = ["emergency_cash_cents", "monthly_living_expenses_cents"]
            if label == "critical":
                reserve_facts.update({
                    "employer_contribution_cents": allocation["employer_match_cents"],
                    "maximum_employer_contribution_cents": state["maximum_monthly_employer_match_cents"],
                    "uncaptured_employer_match_cents": max(
                        0, state["maximum_monthly_employer_match_cents"]
                        - allocation["employer_match_cents"]
                    ),
                    "foregone_employer_match_cents": allocation["critical_reserve_match_forgone_cents"],
                })
                reserve_paths.append("employer_match.tiers")
            reason(code, reserve_facts, reserve_paths)
            action(f"{label}-reserve", "emergency", "action", amount, [code],
                   target=state[target_key])

    for index, debt in enumerate(allocation["debts"]):
        if not debt["total_payment_cents"]:
            continue
        if debt["extra_payment_cents"]:
            code = "HIGH_APR_DEBT"
        else:
            code = "MAINTAIN_DEBT_MINIMUM"
        reason(code, {
            "debt_id": debt["id"], "balance_cents": debt["opening_balance_cents"],
            "apr_rate": debt["apr"],
            "minimum_payment_cents": debt["minimum_payment_cents"],
            "extra_payment_cents": debt["extra_payment_cents"],
            "total_payment_cents": debt["total_payment_cents"],
        }, [f"debts.{index}.id", f"debts.{index}.balance_cents",
            f"debts.{index}.apr", f"debts.{index}.minimum_payment_cents"])
        action(f"debt-{debt['id']}", "debt",
               "action" if debt["extra_payment_cents"] else "maintain",
               debt["total_payment_cents"], [code], debt_id=debt["id"],
               target=0 if debt["extra_payment_cents"] else None)

    if allocation["residual_cash_cents"]:
        reason("UNASSIGNED_SURPLUS", {
            "cash_added_cents": allocation["residual_cash_cents"],
        }, ["monthly_take_home_cents", "monthly_living_expenses_cents", "debts"])
        action("residual-cash", "cash_flow", "information",
               allocation["residual_cash_cents"], ["UNASSIGNED_SURPLUS"])
    reason("BASELINE_ALLOCATION_RETAINED", {
        "equity_weight_rate": state["baseline_equity_weight"],
        "bond_weight_rate": 1 - state["baseline_equity_weight"],
        "months_until_retirement": state["months_until_retirement"],
    }, ["age", "retirement_age"])
    action("illustrative-allocation", "allocation", "information", 0,
           ["BASELINE_ALLOCATION_RETAINED"])

    by_id = {item["id"]: item for item in actions}
    if "critical-reserve" in by_id:
        primary = "critical-reserve"
    elif employee > original and original < full_match_employee:
        primary = "employee-contribution"
    else:
        priority_to_ids = {
            "starter_reserve": ["starter-reserve"],
            "high_apr_debt": [
                f"debt-{debt['id']}" for debt in sorted(
                    (debt for debt in allocation["debts"] if debt["extra_payment_cents"]),
                    key=lambda debt: (-decimal(debt["apr"]),
                                      debt["opening_balance_cents"], debt["id"]),
                )
            ],
            "full_reserve": ["full-reserve"],
        }
        primary = next(
            (candidate for priority in decision["ordered_priorities"]
             for candidate in priority_to_ids[priority] if candidate in by_id),
            "employee-contribution",
        )
    spent = sum(item["monthly_cash_cost_cents"] for item in actions)
    if spent != allocation["resources_cents"] - allocation["living_expenses_cents"]:
        raise AssertionError("Plan actions do not conserve monthly cash")
    return {"primary_action_id": primary, "actions": actions, "reasons": reasons}
