"""Behavior tests for C's progression, with an explicit B-policy substitute."""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.engine.monthly import (  # noqa: E402
    DebtPayment, EngineInvariantError, InfeasibleScenario, MonthlyAllocation,
)
from app.engine.simulation import cents, decimal, run_simulation  # noqa: E402
from app.engine.evaluate import evaluate  # noqa: E402


ASSUMPTIONS = {
    "annual_salary_growth": 0.025,
    "annual_living_cost_growth": 0.025,
    "annual_employee_limit_growth": 0.025,
    "annual_equity_return": 0.06,
    "annual_bond_return": 0.03,
    "annual_cash_return": 0,
    "annual_inflation": 0.025,
    "starter_reserve_months": 1,
    "full_reserve_months": 3,
}
DECISION = {
    "decision_id": "ignored-for-hash",
    "source": "rules_fallback",
    "ordered_priorities": ["starter_reserve", "high_apr_debt", "full_reserve"],
    "model_id": None,
    "prompt_version": "1",
}


def morgan() -> dict:
    return {
        "id": "morgan", "age": 35, "retirement_age": 67,
        "annual_gross_salary_cents": 8_400_000,
        "monthly_take_home_cents": 480_000,
        "monthly_living_expenses_cents": 360_000,
        "employee_contribution_rate": 0.08,
        "contribution_tax_treatment": "traditional",
        "estimated_marginal_income_tax_rate": 0.22,
        "annual_employee_limit_cents": 2_450_000,
        "retirement_balance_cents": 3_500_000,
        "emergency_cash_cents": 360_000,
        "debts": [{
            "id": "morgan-card", "balance_cents": 1_800_000,
            "apr": 0.25, "minimum_payment_cents": 40_000,
        }],
    }


def policy_substitute(profile, inputs, strategy, override, assumptions, decision):
    """A tiny test substitute, not a production implementation of B's policy."""
    rate = (
        decimal(override) if strategy == "custom" and override is not None
        else decimal(profile["employee_contribution_rate"] if strategy == "current" else 0.05)
    )
    employee = cents(Decimal(inputs.gross_monthly_salary_cents) * rate)
    cost_factor = Decimal("0.78") if profile["contribution_tax_treatment"] == "traditional" else Decimal(1)
    cost = cents(Decimal(employee) * cost_factor)
    minimums = sum(debt.minimum_payment_cents for debt in inputs.debts)
    room = inputs.resources_before_retirement_cents - inputs.living_expenses_cents - minimums - cost
    if room < 0 or employee > inputs.employee_limit_cents:
        return MonthlyAllocation(feasible=False, shortfall_cents=max(-room, employee - inputs.employee_limit_cents))
    payments = []
    for debt in inputs.debts:
        extra = 0
        if strategy != "current" and inputs.opening_cash_cents >= inputs.living_expenses_cents and debt.apr >= 0.1:
            extra = min(room, debt.amount_due_cents - debt.minimum_payment_cents)
            room -= extra
        payments.append(DebtPayment(debt.id, debt.minimum_payment_cents, extra))
    match = cents(Decimal(inputs.gross_monthly_salary_cents) * min(rate, Decimal("0.05")))
    return MonthlyAllocation(
        feasible=True,
        employee_contribution_cents=employee,
        employee_contribution_rate=float(rate),
        employee_cash_cost_cents=cost,
        employer_match_cents=match,
        debt_payments=tuple(payments),
        cash_added_cents=room,
    )


def run(profile=None, strategy="adaptive", scenario=None, assumptions=None, allocator=policy_substitute):
    return run_simulation(
        profile or morgan(), strategy, scenario, assumptions or ASSUMPTIONS,
        DECISION, allocator=allocator, equity_weight_fn=lambda _: 0.9,
    )


class SimulationTests(unittest.TestCase):
    def test_morgan_opening_arithmetic_and_independent_current(self):
        adaptive = run()
        allocation = adaptive.opening_allocation
        self.assertIsNotNone(allocation)
        self.assertEqual(allocation.employee_contribution_cents, 35_000)
        self.assertEqual(allocation.employee_cash_cost_cents, 27_300)
        self.assertEqual(allocation.employer_match_cents, 35_000)
        self.assertEqual(allocation.debt_payments[0].extra_cents, 96_380)
        self.assertEqual(allocation.debt_payments[0].total_cents, 136_380)
        self.assertEqual(adaptive.projection.points[1].debt_cents, 1_701_120)
        self.assertEqual(adaptive.projection.points[1].cash_cents, 360_000)
        current = run(strategy="current")
        self.assertEqual(current.opening_allocation.employee_contribution_cents, 56_000)
        self.assertEqual(current.opening_allocation.debt_payments[0].extra_cents, 0)
        self.assertEqual(current.projection.points[1].debt_cents, 1_797_500)
        self.assertEqual(current.projection.points[1].cash_cents, 440_000)
        self.assertEqual(adaptive.projection.points[0].debt_cents, 1_800_000)

    def test_monthly_cap_is_floored(self):
        seen = []

        def recording(*args):
            seen.append(args[1].employee_limit_cents)
            return policy_substitute(*args)

        run(allocator=recording)
        self.assertEqual(seen[0], 2_450_000 // 12)

    def test_anniversary_growth_begins_in_month_thirteen(self):
        profile = morgan()
        profile["age"], profile["retirement_age"] = 60, 62
        seen = []

        def recording(*args):
            inputs = args[1]
            seen.append((inputs.month, inputs.resources_before_retirement_cents, inputs.living_expenses_cents))
            return policy_substitute(*args)

        run(profile, allocator=recording)
        self.assertEqual(seen[11][1:], seen[0][1:])
        self.assertEqual(seen[12][1], cents(Decimal(seen[0][1]) * Decimal("1.025")))
        self.assertEqual(seen[12][2], cents(Decimal(seen[0][2]) * Decimal("1.025")))

    def test_cash_interest_on_opening_cash_only(self):
        profile = morgan()
        profile.update({
            "age": 74, "retirement_age": 75, "employee_contribution_rate": 0,
            "monthly_take_home_cents": 100_000,
            "monthly_living_expenses_cents": 100_000,
            "emergency_cash_cents": 10_000, "debts": [],
        })
        assumptions = {**ASSUMPTIONS, "annual_cash_return": 0.12,
                       "annual_equity_return": 0, "annual_bond_return": 0}
        result = run(profile, strategy="current", assumptions=assumptions)
        self.assertEqual(result.projection.points[1].cash_cents, 10_095)
        self.assertEqual(result.projection.points[1].retirement_balance_cents, 3_500_000)

    def test_final_debt_payment_is_capped_and_minimum_released_next_month(self):
        profile = morgan()
        profile.update({
            "age": 74, "retirement_age": 75,
            "monthly_take_home_cents": 100_000,
            "monthly_living_expenses_cents": 95_000,
            "employee_contribution_rate": 0,
            "debts": [{"id": "small", "balance_cents": 5_000, "apr": 0,
                       "minimum_payment_cents": 40_000}],
        })
        result = run(profile, strategy="current")
        self.assertEqual(result.opening_allocation.debt_payments[0].minimum_cents, 5_000)
        self.assertEqual(result.projection.points[1].debt_cents, 0)
        self.assertEqual(result.projection.debt_free_month, 1)
        self.assertGreater(result.projection.points[2].cash_cents, result.projection.points[1].cash_cents)

    def test_future_failure_blocks_only_that_strategy(self):
        profile = morgan()
        profile.update({"age": 73, "retirement_age": 75})

        def fail_at_thirteen(*args):
            if args[1].month == 13:
                return MonthlyAllocation(feasible=False, shortfall_cents=123)
            return policy_substitute(*args)

        blocked = run(profile, strategy="current", allocator=fail_at_thirteen)
        self.assertFalse(blocked.projection.feasible)
        self.assertEqual(blocked.projection.shortfall_cents, 123)
        self.assertEqual(blocked.projection.points, ())
        self.assertIsNone(blocked.projection.retirement_balance_nominal_cents)
        with self.assertRaises(InfeasibleScenario) as caught:
            run(profile, strategy="custom", scenario={"retirement_age": 75, "employee_contribution_rate": None}, allocator=fail_at_thirteen)
        self.assertEqual(caught.exception.month, 13)

    def test_missing_match_input_blocks_custom_without_budget_error(self):
        def missing(*args):
            return MonthlyAllocation(feasible=False, block_code="MISSING_REQUIRED_INPUT")

        result = run(
            strategy="custom",
            scenario={"retirement_age": 67, "employee_contribution_rate": 0.06},
            allocator=missing,
        )
        self.assertFalse(result.projection.feasible)
        self.assertIsNone(result.projection.shortfall_cents)
        self.assertIn("MISSING_REQUIRED_INPUT", result.warnings)

    def test_allocator_accounting_error_is_not_treated_as_shortfall(self):
        def bad(*args):
            valid = policy_substitute(*args)
            return MonthlyAllocation(**{**valid.__dict__, "cash_added_cents": valid.cash_added_cents + 1})

        with self.assertRaises(EngineInvariantError):
            run(allocator=bad)

    def test_no_debt_and_existing_reserves_have_month_zero_milestones(self):
        profile = morgan()
        profile["debts"] = []
        profile["emergency_cash_cents"] = 1_080_000
        result = run(profile)
        projection = result.projection
        self.assertEqual(projection.debt_free_month, 0)
        self.assertEqual(projection.starter_reserve_month, 0)
        self.assertEqual(projection.full_reserve_month, 0)
        self.assertEqual(projection.points[0].debt_cents, 0)
        self.assertEqual(projection.cumulative_debt_interest_cents, 0)

    def test_negative_amortization_warns_and_never_creates_negative_debt(self):
        profile = morgan()
        profile["debts"] = [{
            "id": "slow", "balance_cents": 100_000,
            "apr": 1.0, "minimum_payment_cents": 100,
        }]
        result = run(profile, strategy="current")
        self.assertIn("NEGATIVE_AMORTIZATION:slow", result.warnings)
        self.assertGreater(result.projection.points[1].debt_cents, 100_000)

    def test_custom_rate_and_retirement_age_are_used_without_changing_baseline(self):
        profile = morgan()
        custom = run(profile, strategy="custom", scenario={
            "retirement_age": 69, "employee_contribution_rate": 0.06,
        })
        baseline = run(profile)
        self.assertEqual(custom.opening_allocation.employee_contribution_cents, 42_000)
        self.assertEqual(custom.projection.retirement_age, 69)
        self.assertEqual(len(custom.projection.points), 409)
        self.assertEqual(len(baseline.projection.points), 385)

    def test_out_of_cap_custom_rate_is_infeasible(self):
        with self.assertRaises(InfeasibleScenario) as caught:
            run(strategy="custom", scenario={
                "retirement_age": 67, "employee_contribution_rate": 0.50,
            })
        self.assertEqual(caught.exception.month, 1)

    def test_custom_rate_fails_at_later_monthly_cap(self):
        profile = morgan()
        profile.update({
            "age": 73, "retirement_age": 75,
            "monthly_take_home_cents": 480_000,
            "monthly_living_expenses_cents": 100_000,
            "debts": [],
        })
        assumptions = {
            **ASSUMPTIONS,
            "annual_salary_growth": 0.10,
            "annual_employee_limit_growth": 0,
        }
        with self.assertRaises(InfeasibleScenario) as caught:
            run(
                profile, strategy="custom",
                scenario={"retirement_age": 75, "employee_contribution_rate": 0.29},
                assumptions=assumptions,
            )
        self.assertEqual(caught.exception.month, 13)
        self.assertGreater(caught.exception.shortfall_cents, 0)

    def test_evaluate_uses_adaptive_first_allocation_and_template(self):
        seen = []

        def build_plan(profile, state, decision, *, allocation):
            seen.append(allocation)
            return {"primary_action_id": "debt", "actions": [], "reasons": []}

        result = evaluate(
            morgan(), None, DECISION,
            assumptions=ASSUMPTIONS, state_fn=lambda _: {"warnings": []},
            allocator=policy_substitute, equity_weight_fn=lambda _: 0.9,
            plan_fn=build_plan,
            template_fn=lambda *args, **kwargs: {
                "state_summary": "Computed facts", "narrative": "Template",
                "source": "template", "changes": [],
            },
            evaluation_model=lambda **items: items,
        )
        self.assertEqual(seen[0].debt_payments[0].extra_cents, 96_380)
        self.assertEqual(result["explanation"]["source"], "template")
        self.assertIsNone(result["projections"]["custom"])
        self.assertEqual(result["projections"]["adaptive"]["points"][1]["debt_cents"], 1_701_120)


if __name__ == "__main__":
    unittest.main()
