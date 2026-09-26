"""Deterministic month-by-month projection; policy amounts come from B.

    opening balances -> interest and capped minimums -> shared allocator
        -> debt payments -> returns on opening assets -> deposits -> point

No profile, decision, or assumptions object is mutated. An allocation is
checked before it can affect a projected balance.
"""

from __future__ import annotations

from dataclasses import asdict
from decimal import Decimal, ROUND_HALF_UP
from importlib import import_module
from typing import Any, Callable

from .monthly import (
    DebtMonth,
    DebtPayment,
    EngineInvariantError,
    InfeasibleScenario,
    MissingHandoffError,
    MonthlyAllocation,
    MonthlyInputs,
    Projection,
    ProjectionPoint,
    SimulationRun,
    Strategy,
)

Allocator = Callable[..., MonthlyAllocation]
EquityWeight = Callable[[int], float]


def get(value: Any, key: str) -> Any:
    """Read a validated Pydantic model or mapping without copying it."""
    return value[key] if isinstance(value, dict) else getattr(value, key)


def optional(value: Any, key: str, default: Any = None) -> Any:
    if isinstance(value, dict):
        return value.get(key, default)
    return getattr(value, key, default)


def decimal(value: Any) -> Decimal:
    if isinstance(value, bool):
        raise TypeError("boolean is not a financial rate")
    result = Decimal(str(value))
    if not result.is_finite():
        raise ValueError("non-finite financial rate")
    return result


def cents(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _grown(amount_cents: int, rate: Any) -> int:
    return cents(Decimal(amount_cents) * (Decimal(1) + decimal(rate)))


def _monthly_interest(balance_cents: int, apr: Any) -> int:
    return cents(Decimal(balance_cents) * decimal(apr) / 12)


def prepare_debts(debts: tuple[Any, ...], balances: dict[str, int]) -> tuple[DebtMonth, ...]:
    """Prepare obligations for injected test allocators.

    Production allocations use B's authoritative interest and capped minimums.
    """
    prepared: list[DebtMonth] = []
    for debt in debts:
        debt_id = str(get(debt, "id"))
        balance = balances[debt_id]
        interest = _monthly_interest(balance, get(debt, "apr")) if balance else 0
        amount_due = balance + interest
        minimum = min(amount_due, int(get(debt, "minimum_payment_cents")))
        prepared.append(
            DebtMonth(
                id=debt_id,
                opening_balance_cents=balance,
                apr=float(get(debt, "apr")),
                interest_cents=interest,
                amount_due_cents=amount_due,
                minimum_payment_cents=minimum,
            )
        )
    return tuple(prepared)


def _as_mapping(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json", exclude_unset=False)
    raise TypeError("B's engine requires a mapping or validated Pydantic model")


def _default_allocator(
    profile: Any, decision: Any,
) -> tuple[Allocator, dict[str, Any]]:
    try:
        policy = import_module("app.engine.policy")
        state_module = import_module("app.engine.state")
    except (ImportError, AttributeError) as exc:
        raise MissingHandoffError("Developer B must provide policy.allocate_month") from exc
    original_profile = _as_mapping(profile)
    original_decision = _as_mapping(decision)
    original_state = state_module.derive_state(original_profile)
    original_debts = {debt["id"]: debt for debt in original_profile["debts"]}

    def allocate(
        _profile: Any, inputs: MonthlyInputs, strategy: Strategy,
        contribution_override: float | None, _assumptions: Any, _decision: Any,
    ) -> MonthlyAllocation:
        month = None
        if inputs.month > 1:
            month_debts = []
            for debt in inputs.debts:
                original = original_debts[debt.id]
                month_debts.append({
                    "id": debt.id, "type": original["type"],
                    "balance_cents": debt.opening_balance_cents,
                    "apr": original["apr"],
                    "minimum_payment_cents": original["minimum_payment_cents"],
                })
            month = {
                "annual_gross_salary_cents": inputs.annual_gross_salary_cents,
                "monthly_resources_before_retirement_cents": inputs.resources_before_retirement_cents,
                "monthly_living_expenses_cents": inputs.living_expenses_cents,
                "annual_employee_limit_cents": inputs.annual_employee_limit_cents,
                "emergency_cash_cents": inputs.opening_cash_cents,
                "debts": month_debts,
            }
        raw = policy.allocate_month(
            original_profile, original_state, original_decision,
            month=month, strategy=strategy,
            employee_contribution_rate=contribution_override,
        )
        debt_months = tuple(
            DebtMonth(
                id=debt["id"],
                opening_balance_cents=debt["opening_balance_cents"],
                apr=float(debt["apr"]),
                interest_cents=debt["interest_cents"],
                amount_due_cents=debt["amount_due_cents"],
                minimum_payment_cents=debt["minimum_payment_cents"],
            ) for debt in raw["debts"]
        )
        return MonthlyAllocation(
            feasible=raw["feasible"],
            block_code="MISSING_REQUIRED_INPUT" if "MISSING_REQUIRED_INPUT" in raw["warnings"] else None,
            employee_contribution_cents=raw["employee_contribution_cents"],
            employee_contribution_rate=raw["employee_contribution_rate"],
            employee_cash_cost_cents=raw["employee_cash_cost_cents"],
            employer_match_cents=raw["employer_match_cents"] or 0,
            debt_payments=tuple(
                DebtPayment(
                    debt["id"], debt["minimum_payment_cents"],
                    debt["extra_payment_cents"],
                ) for debt in raw["debts"]
            ),
            debt_months=debt_months,
            cash_added_cents=raw["total_cash_added_cents"],
            shortfall_cents=raw["shortfall_cents"] or 0,
            warnings=tuple(raw["warnings"]),
            facts={"raw_allocation": raw},
        )

    return allocate, original_state


def _default_equity_weight() -> EquityWeight:
    try:
        return getattr(import_module("app.engine.money"), "equity_weight")
    except (ImportError, AttributeError) as exc:
        raise MissingHandoffError("Developer B must provide money.equity_weight") from exc


def _validate_allocation(inputs: MonthlyInputs, allocation: MonthlyAllocation) -> None:
    if not allocation.feasible:
        return
    money = (
        allocation.employee_contribution_cents,
        allocation.employee_cash_cost_cents,
        allocation.employer_match_cents,
        allocation.cash_added_cents,
    )
    if any(not isinstance(amount, int) or amount < 0 for amount in money):
        raise EngineInvariantError("allocation contains negative or noninteger money")
    if allocation.employee_contribution_cents > inputs.employee_limit_cents:
        raise EngineInvariantError("employee contribution exceeds monthly cap")
    if allocation.employee_contribution_rate is not None:
        rate = decimal(allocation.employee_contribution_rate)
        if not 0 <= rate <= 1:
            raise EngineInvariantError("invalid employee contribution rate")
        if abs(cents(Decimal(inputs.gross_monthly_salary_cents) * rate) - allocation.employee_contribution_cents) > 1:
            raise EngineInvariantError("employee rate and contribution disagree")
    debts = allocation.debt_months or inputs.debts
    if {debt.id for debt in debts} != {debt.id for debt in inputs.debts}:
        raise EngineInvariantError("allocator returned different debt IDs")
    opening_by_id = {debt.id: debt.opening_balance_cents for debt in inputs.debts}
    if any(debt.opening_balance_cents != opening_by_id[debt.id] for debt in debts):
        raise EngineInvariantError("allocator changed an opening debt balance")
    payment_by_id = {p.id: p for p in allocation.debt_payments}
    if len(payment_by_id) != len(allocation.debt_payments):
        raise EngineInvariantError("duplicate debt payment")
    if set(payment_by_id) != {debt.id for debt in debts}:
        raise EngineInvariantError("allocation omits or invents a debt")
    total_payments = 0
    for debt in debts:
        payment = payment_by_id[debt.id]
        if any(
            not isinstance(amount, int) or isinstance(amount, bool)
            for amount in (payment.minimum_cents, payment.extra_cents)
        ):
            raise EngineInvariantError(f"noninteger payment for {debt.id}")
        if payment.minimum_cents != debt.minimum_payment_cents:
            raise EngineInvariantError(f"incorrect minimum for {debt.id}")
        if payment.extra_cents < 0 or payment.total_cents > debt.amount_due_cents:
            raise EngineInvariantError(f"invalid total payment for {debt.id}")
        total_payments += payment.total_cents
    if (
        inputs.resources_before_retirement_cents
        != inputs.living_expenses_cents
        + total_payments
        + allocation.employee_cash_cost_cents
        + allocation.cash_added_cents
    ):
        raise EngineInvariantError("household cash does not balance")


def _blocked(strategy: Strategy, retirement_age: int, shortfall: int) -> Projection:
    return Projection(
        strategy=strategy,
        retirement_age=retirement_age,
        feasible=False,
        shortfall_cents=shortfall if shortfall > 0 else None,
        retirement_balance_nominal_cents=None,
        retirement_balance_today_cents=None,
        cash_nominal_cents=None,
        debt_nominal_cents=None,
        cumulative_debt_interest_cents=None,
        debt_free_month=None,
        starter_reserve_month=None,
        full_reserve_month=None,
        points=(),
    )


def run_simulation(
    profile: Any,
    strategy: Strategy,
    scenario: Any,
    assumptions: Any,
    decision: Any,
    *,
    allocator: Allocator | None = None,
    equity_weight_fn: EquityWeight | None = None,
) -> SimulationRun:
    if strategy not in ("current", "adaptive", "custom"):
        raise ValueError(f"unknown strategy: {strategy}")
    if strategy == "custom" and scenario is None:
        raise ValueError("custom strategy requires a scenario")
    using_b = allocator is None
    initial_state = None
    if allocator is None:
        allocator, initial_state = _default_allocator(profile, decision)
    equity_weight_fn = equity_weight_fn or _default_equity_weight()

    age = int(get(profile, "age"))
    retirement_age = (
        int(get(scenario, "retirement_age"))
        if strategy == "custom"
        else int(get(profile, "retirement_age"))
    )
    total_months = (retirement_age - age) * 12
    if total_months <= 0:
        raise ValueError("retirement age must exceed current age")

    debts = tuple(get(profile, "debts"))
    balances = {str(get(debt, "id")): int(get(debt, "balance_cents")) for debt in debts}
    if len(balances) != len(debts):
        raise ValueError("duplicate debt ID")
    cash = int(get(profile, "emergency_cash_cents"))
    retirement = int(get(profile, "retirement_balance_cents"))
    annual_salary = int(get(profile, "annual_gross_salary_cents"))
    annual_limit = int(get(profile, "annual_employee_limit_cents"))
    living = int(get(profile, "monthly_living_expenses_cents"))
    original_rate = decimal(get(profile, "employee_contribution_rate"))
    treatment = get(profile, "contribution_tax_treatment")
    tax_factor = (
        Decimal(1) - decimal(get(profile, "estimated_marginal_income_tax_rate"))
        if treatment == "traditional"
        else Decimal(1)
    )
    original_monthly_salary = cents(Decimal(annual_salary) / 12)
    original_cash_cost = cents(
        Decimal(cents(Decimal(original_monthly_salary) * original_rate)) * tax_factor
    )
    resources = int(get(profile, "monthly_take_home_cents")) + original_cash_cost
    if initial_state is not None:
        resources = int(initial_state["monthly_resources_before_retirement_cents"])
    employee_limit = annual_limit // 12

    def reserve_reached(months: int) -> bool:
        return cash >= months * living

    debt_free_month = 0 if all(balance == 0 for balance in balances.values()) else None
    starter_reserve_month = 0 if reserve_reached(int(get(assumptions, "starter_reserve_months"))) else None
    full_reserve_month = 0 if reserve_reached(int(get(assumptions, "full_reserve_months"))) else None
    points = [ProjectionPoint(0, retirement, cash, sum(balances.values()))]
    cumulative_interest = 0
    warnings: list[str] = []
    opening_allocation: MonthlyAllocation | None = None

    for month in range(1, total_months + 1):
        if month > 1 and (month - 1) % 12 == 0:
            annual_salary = _grown(annual_salary, get(assumptions, "annual_salary_growth"))
            resources = _grown(resources, get(assumptions, "annual_salary_growth"))
            living = _grown(living, get(assumptions, "annual_living_cost_growth"))
            annual_limit = _grown(annual_limit, get(assumptions, "annual_employee_limit_growth"))
            employee_limit = annual_limit // 12

        prepared = (
            tuple(DebtMonth(
                id=str(get(debt, "id")),
                opening_balance_cents=balances[str(get(debt, "id"))],
                apr=float(get(debt, "apr")),
                interest_cents=0,
                amount_due_cents=balances[str(get(debt, "id"))],
                minimum_payment_cents=min(
                    balances[str(get(debt, "id"))], int(get(debt, "minimum_payment_cents"))
                ),
            ) for debt in debts)
            if using_b else prepare_debts(debts, balances)
        )
        inputs = MonthlyInputs(
            month=month,
            months_until_retirement=total_months - month + 1,
            annual_gross_salary_cents=annual_salary,
            annual_employee_limit_cents=annual_limit,
            gross_monthly_salary_cents=cents(Decimal(annual_salary) / 12),
            resources_before_retirement_cents=resources,
            living_expenses_cents=living,
            employee_limit_cents=employee_limit,
            opening_cash_cents=cash,
            opening_retirement_balance_cents=retirement,
            debts=prepared,
        )
        contribution_override = (
            optional(scenario, "employee_contribution_rate")
            if strategy == "custom"
            else None
        )
        desired_custom_cents = None
        if strategy == "custom" and contribution_override is not None:
            desired_custom_cents = cents(
                (Decimal(annual_salary) / 12) * decimal(contribution_override)
            )
            if desired_custom_cents > employee_limit:
                raise InfeasibleScenario(month, desired_custom_cents - employee_limit)
        allocation = allocator(
            profile,
            inputs,
            strategy,
            contribution_override,
            assumptions,
            decision,
        )
        if not isinstance(allocation, MonthlyAllocation):
            raise EngineInvariantError("allocator returned an unexpected type")
        if month == 1:
            opening_allocation = allocation
        if not allocation.feasible:
            shortfall = allocation.shortfall_cents
            if shortfall < 0:
                raise EngineInvariantError("shortfall cannot be negative")
            if strategy == "custom" and allocation.block_code != "MISSING_REQUIRED_INPUT":
                raise InfeasibleScenario(month, shortfall)
            warnings.append(f"{strategy.upper()}_INFEASIBLE_MONTH_{month}")
            if allocation.block_code:
                warnings.append(allocation.block_code)
            warnings.extend(allocation.warnings)
            return SimulationRun(
                _blocked(strategy, retirement_age, shortfall),
                opening_allocation,
                tuple(dict.fromkeys(warnings)),
            )
        _validate_allocation(inputs, allocation)
        if desired_custom_cents is not None and allocation.employee_contribution_cents != desired_custom_cents:
            raise EngineInvariantError("fixed custom contribution was changed")
        warnings.extend(allocation.warnings)
        payments = {payment.id: payment for payment in allocation.debt_payments}
        for debt in allocation.debt_months or prepared:
            payment = payments[debt.id]
            closing = debt.amount_due_cents - payment.total_cents
            if closing < 0:
                raise EngineInvariantError("negative debt balance")
            balances[debt.id] = closing
            cumulative_interest += debt.interest_cents
            if payment.total_cents < debt.interest_cents:
                warnings.append(f"NEGATIVE_AMORTIZATION:{debt.id}")

        equity = float(equity_weight_fn(inputs.months_until_retirement))
        if not 0 <= equity <= 1:
            raise EngineInvariantError("invalid equity weight")
        annual_return = (
            equity * float(get(assumptions, "annual_equity_return"))
            + (1 - equity) * float(get(assumptions, "annual_bond_return"))
        )
        if annual_return <= -1:
            raise EngineInvariantError("invalid annual investment return")
        retirement_growth = (1 + annual_return) ** (1 / 12)
        retirement = cents(Decimal(str(retirement * retirement_growth)))
        retirement += allocation.employee_contribution_cents + allocation.employer_match_cents

        annual_cash_return = float(get(assumptions, "annual_cash_return"))
        if annual_cash_return <= -1:
            raise EngineInvariantError("invalid annual cash return")
        cash_growth = (1 + annual_cash_return) ** (1 / 12)
        cash = cents(Decimal(str(cash * cash_growth))) + allocation.cash_added_cents
        if cash < 0 or retirement < 0:
            raise EngineInvariantError("negative asset balance")

        if debt_free_month is None and all(balance == 0 for balance in balances.values()):
            debt_free_month = month
        if starter_reserve_month is None and reserve_reached(int(get(assumptions, "starter_reserve_months"))):
            starter_reserve_month = month
        if full_reserve_month is None and reserve_reached(int(get(assumptions, "full_reserve_months"))):
            full_reserve_month = month
        points.append(ProjectionPoint(month, retirement, cash, sum(balances.values())))

    inflation_factor = (1 + float(get(assumptions, "annual_inflation"))) ** (total_months / 12)
    if inflation_factor <= 0:
        raise EngineInvariantError("invalid inflation factor")
    projection = Projection(
        strategy=strategy,
        retirement_age=retirement_age,
        feasible=True,
        shortfall_cents=None,
        retirement_balance_nominal_cents=retirement,
        retirement_balance_today_cents=cents(Decimal(str(retirement / inflation_factor))),
        cash_nominal_cents=cash,
        debt_nominal_cents=sum(balances.values()),
        cumulative_debt_interest_cents=cumulative_interest,
        debt_free_month=debt_free_month,
        starter_reserve_month=starter_reserve_month,
        full_reserve_month=full_reserve_month,
        points=tuple(points),
    )
    return SimulationRun(projection, opening_allocation, tuple(dict.fromkeys(warnings)))


def simulate(
    profile: Any,
    strategy: Strategy,
    scenario: Any,
    assumptions: Any,
    decision: Any,
    *,
    allocator: Allocator | None = None,
    equity_weight_fn: EquityWeight | None = None,
) -> Projection:
    """Documented public simulation entry point."""
    return run_simulation(
        profile,
        strategy,
        scenario,
        assumptions,
        decision,
        allocator=allocator,
        equity_weight_fn=equity_weight_fn,
    ).projection


def projection_dict(projection: Projection) -> dict[str, Any]:
    result = asdict(projection)
    result["points"] = [asdict(point) for point in projection.points]
    return result
