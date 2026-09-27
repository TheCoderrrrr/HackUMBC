// Wire types for contracts/openapi.json (schema version "1"). Money is integer cents.

export type Priority = "starter_reserve" | "high_apr_debt" | "full_reserve";
export type PlanningPreference = "balanced" | "cash_security" | "debt_reduction";

export interface MatchTier {
  employee_rate_from: number;
  employee_rate_to: number;
  match_per_employee_dollar: number;
}

export interface Debt {
  id: string;
  type: "credit_card" | "student_loan" | "other";
  balance_cents: number;
  apr: number;
  minimum_payment_cents: number;
}

export interface FinancialProfile {
  schema_version: "1";
  id: string;
  name: string;
  as_of_date: string;
  currency: "USD";
  source: "demo" | "plaid_sandbox";
  age: number;
  retirement_age: number;
  annual_gross_salary_cents: number;
  monthly_take_home_cents: number;
  monthly_living_expenses_cents: number;
  annual_employee_limit_cents: number;
  employee_contribution_rate: number;
  contribution_tax_treatment: "traditional" | "roth";
  estimated_marginal_income_tax_rate: number;
  retirement_balance_cents: number;
  emergency_cash_cents: number;
  employer_match: { status: "confirmed" | "none" | "unknown"; fully_vested: boolean; tiers: MatchTier[] };
  debts: Debt[];
  planning_preference?: PlanningPreference;
  provenance?: Record<string, unknown>;
}

export interface Scenario {
  retirement_age: number;
  employee_contribution_rate: number | null;
}

export interface EvaluateRequest {
  profile: FinancialProfile;
  scenario: Scenario | null;
  previous_decision_id: string | null;
}

export interface FinancialState {
  months_until_retirement: number;
  gross_monthly_salary_cents: number;
  current_employee_contribution_cents: number;
  current_employee_cash_cost_cents: number;
  monthly_resources_before_retirement_cents: number;
  monthly_required_debt_payments_cents: number;
  monthly_allocatable_budget_cents: number;
  current_monthly_surplus_cents: number;
  emergency_months: number;
  critical_reserve_target_cents: number;
  starter_reserve_target_cents: number;
  full_reserve_target_cents: number;
  employee_rate_for_full_match: number | null;
  current_monthly_employer_match_cents: number | null;
  maximum_monthly_employer_match_cents: number | null;
  match_capture_fraction: number | null;
  high_interest_debt_cents: number;
  highest_debt_apr: number | null;
  baseline_equity_weight: number;
  warnings: string[];
}

export type ActionCategory = "cash_flow" | "contribution" | "emergency" | "debt" | "allocation";

export interface RecommendationAction {
  id: string;
  rank: number;
  category: ActionCategory;
  status: "action" | "maintain" | "blocked" | "information";
  monthly_cash_cost_cents: number;
  employee_contribution_cents: number | null;
  employee_contribution_rate: number | null;
  debt_id: string | null;
  target_balance_cents: number | null;
  reason_codes: string[];
}

export interface Reason {
  code: string;
  template_key: string;
  facts: Record<string, string | number | boolean | null>;
  input_paths: string[];
}

export interface ProjectionPoint {
  month: number;
  retirement_balance_cents: number;
  cash_cents: number;
  debt_cents: number;
}

export interface Projection {
  strategy: "current" | "adaptive" | "custom";
  retirement_age: number;
  feasible: boolean;
  shortfall_cents: number | null;
  retirement_balance_nominal_cents: number | null;
  retirement_balance_today_cents: number | null;
  cash_nominal_cents: number | null;
  debt_nominal_cents: number | null;
  cumulative_debt_interest_cents: number | null;
  debt_free_month: number | null;
  starter_reserve_month: number | null;
  full_reserve_month: number | null;
  points: ProjectionPoint[];
}

export interface ModelAssumptions {
  annual_equity_return: number;
  annual_bond_return: number;
  annual_cash_return: number;
  annual_inflation: number;
  annual_salary_growth: number;
  annual_living_cost_growth: number;
  annual_employee_limit_growth: number;
  high_interest_apr_threshold: number;
  retirement_total_saving_target: number;
  critical_reserve_cap_cents: number;
  starter_reserve_months: number;
  full_reserve_months: number;
  returns_net_of_fees: boolean;
  glide_path: { years_to_retirement: number; equity_weight: number }[];
  limitations: string[];
}

export interface Evaluation {
  schema_version: "1";
  model_version: string;
  policy_version: string;
  profile_id: string;
  input_hash: string;
  financial_state: FinancialState;
  plan: { primary_action_id: string | null; actions: RecommendationAction[]; reasons: Reason[] };
  assumptions: ModelAssumptions;
  projections: { current: Projection; adaptive: Projection; custom: Projection | null };
  warnings: string[];
  decision_summary: {
    decision_id: string;
    source: "ai" | "rules_fallback";
    model_id: string | null;
    prompt_version: string;
    ordered_priorities: Priority[];
    rationale: { priority: Priority; summary: string; evidence_paths: string[]; tradeoff: string }[];
    constraint_checks: { code: string; passed: boolean }[];
    fallback_reason: string | null;
  };
  explanation: {
    state_summary: string;
    narrative: string;
    source: "ai" | "template";
    changes: { field_path: string; before: string | number | boolean | null; after: string | number | boolean | null }[];
  };
}

export interface Health {
  status: "ok";
  schema_version: string;
  model_version: string;
  policy_version: string;
  plaid_enabled: boolean;
}

export interface ErrorBody {
  code: string;
  message: string;
  field_paths: string[];
  retryable: boolean;
}

// Scenario history (Tiger Data). Saved runs are rebuilt on the server from their inputs.
export interface RunSummary {
  run_id: string;
  profile_id: string;
  label: string;
  created_at: string;
  as_of_date: string;
  scenario: Scenario | null;
  primary_strategy: "adaptive" | "custom";
  retirement_age: number;
  final_retirement_balance_cents: number | null;
  decision_source: "ai" | "rules_fallback";
  model_id: string | null;
  prompt_version: string;
  model_version: string;
  policy_version: string;
  input_hash: string;
}

export interface YearValues {
  retirement_balance_cents: number;
  cash_cents: number;
  debt_cents: number;
}

export interface Comparison {
  profile_id: string;
  as_of_date: string;
  base: RunSummary;
  other: RunSummary;
  years: { year: number; month: number; projected_on: string; base: YearValues | null; other: YearValues | null }[];
  horizons: { years: number; month: number; projected_on: string; base: YearValues | null; other: YearValues | null }[];
  source: "tiger_data";
  method: string;
}

export interface HistoryStatus {
  enabled: boolean;
  available: boolean;
}

// Plan styles: the same profile under each planning preference's own rule order (no AI).
export interface StyleYear {
  year: number;
  month: number;
  retirement_balance_cents: number;
  cash_cents: number;
  debt_cents: number;
}

export interface StyleOutcome {
  style: PlanningPreference | null;
  label: string;
  ordered_priorities: Priority[] | null;
  retirement_age: number;
  debt_free_month: number | null;
  starter_reserve_month: number | null;
  full_reserve_month: number | null;
  cumulative_debt_interest_cents: number | null;
  retirement_balance_nominal_cents: number | null;
  retirement_balance_today_cents: number | null;
  yearly: StyleYear[];
}

export interface PlanStyles {
  profile_id: string;
  as_of_date: string;
  model_version: string;
  policy_version: string;
  current: StyleOutcome;
  styles: StyleOutcome[];
  method: string;
}
