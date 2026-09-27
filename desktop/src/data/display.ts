import type { Evaluation, FinancialProfile, Projection } from "../api/types";
import { money, moneyExact, percent } from "./format";

// Maps an engine evaluation onto what the screens show. Every figure comes from the
// profile or the response; this file only selects, labels and sums fields.

export type DataMode = "saved" | "live" | "lastLive";
export type CashKind = "retirement" | "debt" | "emergency" | "remaining";

export const DATA_MODE_LABEL: Record<DataMode, string> = {
  saved: "Saved demo calculation",
  live: "Live calculation",
  lastLive: "Last live calculation",
};

// One wording for the three reorderable priorities everywhere in the app.
export { PRIORITY_LABEL } from "./styles";

export const DISCLOSURE = {
  fictional: "Fictional customer • Synthetic data • Not affiliated with or endorsed by T. Rowe Price.",
  illustrative: "Illustrative projection",
  allocationLabel: "Illustrative allocation — not a specific T. Rowe Price fund",
  allocationCopy:
    "This prototype retains an illustrative target-date allocation. Your financial context changes contributions and cash priorities; it does not establish a suitable alternative portfolio.",
};

export interface DisplayDebt {
  id: string;
  name: string;
  balanceCents: number;
  apr: number;
  minimumCents: number;
  extraCents: number;
}

export interface CashPriority {
  kind: CashKind;
  title: string;
  amountCents: number;
}

export interface Display {
  profile: FinancialProfile;
  evaluation: Evaluation;
  yearsToRetirement: number;
  currentRate: number;
  rate: number;
  employeeCents: number;
  employerCents: number | null;
  takeHomeCostCents: number;
  matchCaptured: boolean;
  debts: DisplayDebt[];
  cash: CashPriority[];
  emergencyMonths: number;
  starterMonths: number;
  fullMonths: number;
  starterTargetCents: number;
  fullTargetCents: number;
  equityWeight: number;
  nextStep: { headline: string; amountCents: number | null; detail: string };
  origin: string;
}

export function debtName(type: string): string {
  if (type === "credit_card") return "Credit card";
  if (type === "student_loan") return "Student loan";
  return "Loan";
}

export function originLabel(evaluation: Evaluation, mode: DataMode): string {
  if (evaluation.decision_summary.source === "rules_fallback") return "Rules fallback";
  return mode === "saved" ? "Saved AI-assisted priorities" : "AI-assisted priorities";
}

export function buildDisplay(profile: FinancialProfile, evaluation: Evaluation, mode: DataMode): Display {
  const state = evaluation.financial_state;
  const actions = evaluation.plan.actions;
  const contribution = actions.find((a) => a.category === "contribution");
  const currentRate = profile.employee_contribution_rate;
  const rate = contribution?.employee_contribution_rate ?? currentRate;
  const employeeCents = contribution?.employee_contribution_cents ?? state.current_employee_contribution_cents;
  const takeHomeCostCents = contribution?.monthly_cash_cost_cents ?? state.current_employee_cash_cost_cents;

  const fullMatchRate = state.employee_rate_for_full_match;
  const matchCaptured = fullMatchRate !== null && rate + 1e-9 >= fullMatchRate;
  let employerCents: number | null = null;
  if (matchCaptured) employerCents = state.maximum_monthly_employer_match_cents;
  else if (Math.abs(rate - currentRate) < 1e-9) employerCents = state.current_monthly_employer_match_cents;

  const debts: DisplayDebt[] = profile.debts.map((d) => {
    const action = actions.find((a) => a.debt_id === d.id);
    return {
      id: d.id,
      name: debtName(d.type),
      balanceCents: d.balance_cents,
      apr: d.apr,
      minimumCents: d.minimum_payment_cents,
      extraCents: action ? Math.max(action.monthly_cash_cost_cents - d.minimum_payment_cents, 0) : 0,
    };
  });
  const cost = (category: string) =>
    actions.filter((a) => a.category === category).reduce((sum, a) => sum + a.monthly_cash_cost_cents, 0);
  const cash: CashPriority[] = [
    { kind: "retirement", title: "Retirement cost", amountCents: takeHomeCostCents },
    { kind: "debt", title: "Extra debt payment", amountCents: debts.reduce((s, d) => s + d.extraCents, 0) },
    { kind: "emergency", title: "Emergency savings", amountCents: cost("emergency") },
    { kind: "remaining", title: "Remaining cash", amountCents: cost("cash_flow") },
  ];

  const living = profile.monthly_living_expenses_cents;
  const starterMonths = evaluation.assumptions.starter_reserve_months;
  const fullMonths = evaluation.assumptions.full_reserve_months;

  return {
    profile,
    evaluation,
    yearsToRetirement: profile.retirement_age - profile.age,
    currentRate,
    rate,
    employeeCents,
    employerCents,
    takeHomeCostCents,
    matchCaptured,
    debts,
    cash,
    emergencyMonths: state.emergency_months,
    starterMonths,
    fullMonths,
    starterTargetCents: state.starter_reserve_target_cents || Math.round(living * starterMonths),
    fullTargetCents: state.full_reserve_target_cents || Math.round(living * fullMonths),
    equityWeight: state.baseline_equity_weight,
    nextStep: nextStep(evaluation, debts, cash, rate, currentRate, matchCaptured),
    origin: originLabel(evaluation, mode),
  };
}

function nextStep(
  evaluation: Evaluation,
  debts: DisplayDebt[],
  cash: CashPriority[],
  rate: number,
  currentRate: number,
  matchCaptured: boolean,
): Display["nextStep"] {
  const aiDetail = evaluation.explanation.source === "ai" ? evaluation.explanation.narrative : null;
  const primary = evaluation.plan.actions.find((a) => a.id === evaluation.plan.primary_action_id);
  const debt = primary?.debt_id ? debts.find((d) => d.id === primary.debt_id) : undefined;

  if (debt && debt.extraCents > 0) {
    return {
      headline: matchCaptured ? "Keep the match. Tackle the debt." : `Pay down your ${debt.name.toLowerCase()}.`,
      amountCents: debt.extraCents,
      detail: aiDetail ?? ` extra toward your ${debt.name.toLowerCase()} each month.`,
    };
  }
  if (primary?.category === "emergency") {
    const amount = cash.find((c) => c.kind === "emergency")?.amountCents ?? 0;
    return {
      headline: "Build your emergency savings.",
      amountCents: amount > 0 ? amount : null,
      detail: aiDetail ?? (amount > 0 ? " into reserves each month." : "Grow your cash reserve before other goals."),
    };
  }
  const remaining = cash.find((c) => c.kind === "remaining")?.amountCents ?? 0;
  const headline =
    rate > currentRate + 1e-9
      ? `Raise your contribution to ${percent(rate)}.`
      : rate < currentRate - 1e-9
        ? `Contribute ${percent(rate)} for now.`
        : `Keep contributing ${percent(rate)}.`;
  return {
    headline,
    amountCents: null,
    detail:
      aiDetail ??
      (remaining > 0
        ? `Your plan is on course. The remaining ${money(remaining)} each month stays yours to direct.`
        : "Your plan is on course to maintain."),
  };
}

/** Balance at the start of each year from today, `years + 1` values. */
export function yearlyBalances(projection: Projection, years: number): number[] {
  if (projection.points.length === 0) return [];
  return Array.from({ length: Math.max(years, 0) + 1 }, (_, year) => balanceAtYear(projection, year));
}

export function balanceAtYear(projection: Projection, year: number): number {
  let value = projection.points[0]?.retirement_balance_cents ?? 0;
  for (const point of projection.points) {
    if (point.month <= year * 12) value = point.retirement_balance_cents;
    else break;
  }
  return value;
}

export function pointAtMonth(projection: Projection, month: number) {
  let found = projection.points[0];
  for (const point of projection.points) {
    if (point.month <= month) found = point;
    else break;
  }
  return found;
}

/** Explanation copy assembled from engine fields, for "Why this plan?". */
export function explanationSteps(display: Display): { title: string; detail: string }[] {
  const { profile, debts } = display;
  const minimums = debts.reduce((s, d) => s + d.minimumCents, 0);
  const steps = [
    {
      title: "Protect the essentials",
      detail:
        minimums > 0
          ? `${money(profile.monthly_living_expenses_cents)} for living costs and the ${money(minimums)} debt minimum come first.`
          : `${money(profile.monthly_living_expenses_cents)} for living costs comes first.`,
    },
  ];
  if (display.matchCaptured && display.employerCents !== null) {
    steps.push({
      title: "Keep the full employer match",
      detail: `Your ${percent(display.rate)} contribution adds ${money(display.employeeCents)}. Your employer adds another ${money(display.employerCents)}.`,
    });
  }
  const paying = debts.find((d) => d.extraCents > 0);
  const remaining = display.cash.find((c) => c.kind === "remaining")?.amountCents ?? 0;
  const emergency = display.cash.find((c) => c.kind === "emergency")?.amountCents ?? 0;
  if (paying) {
    steps.push({
      title: "Pay down high-interest debt",
      detail: `The remaining ${moneyExact(paying.extraCents)} goes toward your ${paying.name.toLowerCase()} each month.`,
    });
  } else if (emergency > 0) {
    steps.push({
      title: "Build emergency savings",
      detail: `${moneyExact(emergency)} goes into reserves each month.`,
    });
  } else if (remaining > 0) {
    steps.push({
      title: "Keep the rest flexible",
      detail: `The remaining ${money(remaining)} each month stays yours to direct.`,
    });
  }
  return steps;
}

/**
 * Getting started walks this month's budget in four steps: essentials, match and retirement,
 * the plan style's goals, and what's left. Every budget line belongs to exactly one step.
 */
export const MONTH_STEP_LINES = [["living", "minimums"], ["retirement"], ["debt", "emergency"], ["remaining"]] as const;

/** Cents per step of MONTH_STEP_LINES. */
export function monthStepCents(lines: BudgetLine[]): number[] {
  return MONTH_STEP_LINES.map((keys) => lines.filter((l) => (keys as readonly string[]).includes(l.key)).reduce((s, l) => s + l.cents, 0));
}

export interface BudgetLine {
  key: string;
  label: string;
  note: string;
  cents: number;
}

/**
 * This month's money, laid out so it visibly adds up. Take-home pay is measured after the
 * current 401(k) contribution, so the engine plans with take-home + that contribution's
 * after-tax cost (`monthly_resources_before_retirement_cents`). Every line comes from the
 * engine's plan; `total` must equal `toPlan` (tested on real engine output).
 */
export function monthBudget(display: Display): {
  takeHomeCents: number;
  currentContributionCents: number;
  toPlanCents: number;
  lines: BudgetLine[];
  totalCents: number;
} {
  const { profile, evaluation } = display;
  const state = evaluation.financial_state;
  const cash = Object.fromEntries(display.cash.map((c) => [c.kind, c.amountCents])) as Record<CashKind, number>;
  const minimums = display.debts.reduce((s, d) => s + d.minimumCents, 0);
  const lines: BudgetLine[] = [
    { key: "living", label: "Living costs", note: "Rent, food and bills", cents: profile.monthly_living_expenses_cents },
    { key: "minimums", label: "Minimum debt payments", note: "Required on every debt", cents: minimums },
    { key: "retirement", label: "Retirement contribution", cents: cash.retirement,
      note: profile.contribution_tax_treatment === "roth"
        ? `${percent(display.rate)} of pay (Roth: no upfront tax saving)`
        : `${percent(display.rate)} of pay, net of the income tax it saves` },
    { key: "debt", label: "Extra toward debt", note: "On top of the minimums", cents: cash.debt },
    { key: "emergency", label: "Emergency savings", note: "Into your cash cushion", cents: cash.emergency },
    { key: "remaining", label: "Left over", note: "Yours to spend or save", cents: cash.remaining },
  ].filter((l) => l.cents > 0 || l.key === "living" || l.key === "retirement");
  return {
    takeHomeCents: profile.monthly_take_home_cents,
    currentContributionCents: state.current_employee_cash_cost_cents,
    toPlanCents: state.monthly_resources_before_retirement_cents,
    lines,
    totalCents: lines.reduce((s, l) => s + l.cents, 0),
  };
}
