import type { PlanningPreference, PlanStyles, Priority, StyleOutcome } from "../api/types";

/**
 * Plain-language copy for the three plan styles. It describes each idea, not the exact rule:
 * the precise priority order is always taken from the backend (`ordered_priorities` from
 * /v1/plan-styles), so the words can't drift from what the engine does.
 */
export const STYLE_INFO: Record<PlanningPreference, {
  label: string;
  tagline: string;
  intro: string;
  pros: string;
  cons: string;
  color: string;
}> = {
  balanced: {
    label: "Balanced",
    tagline: "A bit of both",
    intro: "Balances paying down expensive debt with building an emergency fund, so neither one is ignored.",
    pros: "You make steady progress on both fronts. Interest shrinks while a cash cushion grows, so one surprise bill is less likely to push you back into debt.",
    cons: "Because the extra money is split, neither goal finishes as fast as it would on its own.",
    color: "var(--accent)",
  },
  cash_security: {
    label: "Cash security first",
    tagline: "Safety net first",
    intro: "Builds a full emergency fund before putting extra money toward debt.",
    pros: "A good fit when income is uncertain or a big bill could come at any time: you'll have months of expenses set aside sooner.",
    cons: "Expensive debt sticks around longer, so you pay more interest in the meantime.",
    color: "#c4a7f5",
  },
  debt_reduction: {
    label: "Debt payoff first",
    tagline: "Clear expensive debt fast",
    intro: "Sends extra money to your highest-interest debt before building more savings.",
    pros: "Usually the cheapest path. Each dollar that clears a 20–30% card saves more than it could reliably earn anywhere else.",
    cons: "Your cash cushion stays small until the debt is gone, so an emergency could mean borrowing again.",
    color: "#f2c46d",
  },
};

export const STYLE_ORDER: PlanningPreference[] = ["balanced", "cash_security", "debt_reduction"];

export const PRIORITY_LABEL: Record<Priority, string> = {
  starter_reserve: "One-month cushion",
  high_apr_debt: "High-interest debt",
  full_reserve: "Full emergency fund",
};

const signature = (o: StyleOutcome) =>
  [o.debt_free_month, o.full_reserve_month, o.starter_reserve_month, o.cumulative_debt_interest_cents,
    o.retirement_balance_nominal_cents].join("|");

/** False when every style leads to the same projection, e.g. no high-interest debt and a full cushion. */
export function stylesDiffer(data: PlanStyles): boolean {
  return new Set(data.styles.map(signature)).size > 1;
}

export function outcomeFor(data: PlanStyles, style: PlanningPreference): StyleOutcome | undefined {
  return data.styles.find((s) => s.style === style);
}
