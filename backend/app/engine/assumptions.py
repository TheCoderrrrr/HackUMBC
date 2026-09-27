"""Published illustrative policy and modeling assumptions."""

from __future__ import annotations

SCHEMA_VERSION = "1"
MODEL_VERSION = "2.0.0"
POLICY_VERSION = "2.0.0"

MODEL_ASSUMPTIONS = {
    "annual_equity_return": 0.06,
    "annual_bond_return": 0.03,
    "annual_cash_return": 0.0,
    "annual_inflation": 0.025,
    "annual_salary_growth": 0.025,
    "annual_living_cost_growth": 0.025,
    "annual_employee_limit_growth": 0.025,
    "high_interest_apr_threshold": 0.10,
    "retirement_total_saving_target": 0.15,
    "critical_reserve_cap_cents": 100_000,
    "starter_reserve_months": 1,
    "full_reserve_months": 3,
    "returns_net_of_fees": True,
    "fund_model": None,
    "glide_path": [
        {"years_to_retirement": 30, "equity_weight": 0.90},
        {"years_to_retirement": 20, "equity_weight": 0.80},
        {"years_to_retirement": 10, "equity_weight": 0.65},
        {"years_to_retirement": 0, "equity_weight": 0.50},
    ],
    "limitations": [
        "Illustrative nominal assumptions, not sponsor forecasts or a specific fund.",
        "No volatility, retirement spending, withdrawals, or withdrawal taxation.",
        "Traditional contribution cash cost uses a simplified fixed marginal tax adjustment.",
        "Annualized employee cap excludes catch-up contributions and does not measure remaining legal current-year room.",
        "Future cap growth is a planning assumption, not future law.",
        "Debt APR and minimums remain fixed; real card conventions can differ.",
        "No new borrowing, variable-rate debts, vesting schedules, or employer true-ups.",
        "Reserve targets and 15% combined saving target are heuristics, not retirement adequacy estimates.",
    ],
}
