/** Mirrors backend/app/fund_api.py and the shortlist models in backend/app/funds.py. */

export type AccountType = "401k" | "ira";
export type RiskTolerance = "conservative" | "moderate" | "growth";
export type AvailabilityLabel =
  | "in_supplied_plan_menu"
  | "research_candidate_plan_menu_unconfirmed"
  | "discoverable_not_confirmed_purchasable";
export type ExclusionReason =
  | "NOT_IN_PLAN_MENU" | "UNAVAILABLE" | "INCOMPLETE_FACTS" | "STALE_FACTS"
  | "NOT_TARGET_DATE" | "NON_USD" | "POOR_HORIZON_FIT" | "POOR_RISK_FIT";

export interface FundShortlistQuery {
  account_type: AccountType;
  retirement_year: number;
  risk_tolerance: RiskTolerance;
  plan_menu_fund_ids?: string[] | null;
  max_results?: number;
}

export interface CatalogEntry {
  fund_id: string;
  name: string;
  issuer: string;
  class_name: string;
  ticker: string | null;
  target_year: number;
}

export interface CatalogSummary {
  catalog_version: string;
  published_on: string;
  reviewed_by: string;
  review_note: string;
  funds: CatalogEntry[];
}

export interface HistoricalReturn {
  period_years: number;
  annualized_return_rate: number;
  as_of_date: string;
  source: string;
}

export interface HypotheticalScenario {
  label: "low" | "base" | "high";
  equity_assumption_rate: number;
  bond_assumption_rate: number;
  other_assumption_rate: number;
  annual_net_return_rate: number;
  years: number;
  hypothetical_start_cents: number;
  hypothetical_end_cents: number;
  allocation_assumption: "current_weights_held_constant";
}

export interface FundRecommendation {
  fund_id: string;
  share_class_id: string;
  name: string;
  account_type: AccountType;
  availability_label: AvailabilityLabel;
  source: string;
  source_url: string;
  prospectus_url: string;
  facts_as_of_date: string;
  expense_ratio_source: string;
  expense_ratio_as_of_date: string;
  expense_ratio: number;
  equity_weight: number;
  bond_weight: number;
  other_weight: number;
  risk_band: number;
  risk_method: "current_equity_weight_proxy_not_volatility";
  risk_inputs: Record<string, number>;
  target_year: number;
  score: number;
  score_components: { horizon_fit: number; risk_fit: number; fee_fit: number; data_completeness: number };
  reason_codes: string[];
  hypothetical_scenarios: HypotheticalScenario[];
  historical_returns: HistoricalReturn[];
}

export interface FundShortlist {
  account_type: AccountType;
  as_of_date: string;
  recommendations: FundRecommendation[];
  excluded: { fund_id: string; reason_code: ExclusionReason }[];
  plan_menu_status: "unknown" | "confirmed" | "not_applicable";
  score_weights: Record<string, number>;
  assumption_set_version: string;
  assumption_set_as_of_date: string;
  hypothetical_disclosure: string;
}

export interface DocumentLink {
  title: string;
  form: string;
  filed_date: string;
  url: string;
}

export interface FundDetail {
  fund_id: string;
  issuer: string;
  registrant: string;
  series_id: string;
  share_class_id: string;
  class_name: string;
  ticker: string | null;
  target_year: number;
  fees: {
    gross_expense_ratio: number;
    acquired_fund_fees: number;
    fee_waiver: number;
    net_expense_ratio: number;
    applied_expense_ratio: number;
    waiver_active: boolean;
    waiver_ends: string | null;
    waiver_terms: string;
    as_of_date: string;
    evidence_url: string;
  };
  allocation: {
    as_of_date: string;
    reported_categories: { label: string; percent_of_net_assets: number; bucket: "equity" | "bond" | "other" }[];
    mapping_note: string;
    evidence_url: string;
  };
  glide_path: string;
  prospectus: DocumentLink;
  holdings_report: DocumentLink;
  caveats: string[];
}

export interface FundShortlistEnvelope {
  catalog_version: string;
  catalog_published_on: string;
  catalog_reviewed_by: string;
  unmatched_plan_menu_ids: string[];
  shortlist: FundShortlist;
  details: Record<string, FundDetail>;
}
