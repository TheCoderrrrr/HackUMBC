import type { ModelAssumptions } from "../api/types";
import { money, percent } from "./format";

/**
 * Key terms shown in "?" popovers. Where a definition quotes a model number, it reads it from the
 * engine's own assumptions (Evaluation.assumptions), so the text always matches the backend.
 */
export type TermId =
  | "plan-style" | "emergency-fund" | "cushion" | "small-reserve" | "high-interest-debt" | "apr"
  | "employer-match" | "target-date-fund" | "glide-path" | "current-habits" | "todays-dollars"
  | "projection" | "compound-growth";

type Entry = { title: string; text: (a?: ModelAssumptions) => string };

const months = (n: number) => `${n} ${n === 1 ? "month" : "months"}`;

export const GLOSSARY: Record<TermId, Entry> = {
  "plan-style": {
    title: "Plan style",
    text: () => "Decides what your extra money pays for first once the basics are covered: a one-month cushion, high-interest debt, or the full emergency fund.",
  },
  "emergency-fund": {
    title: "Emergency fund",
    text: (a) => `Cash set aside for surprises, like a car repair or a gap in income.${a ? ` ARM's full target is ${months(a.full_reserve_months)} of living costs.` : ""}`,
  },
  cushion: {
    title: "One-month cushion",
    text: (a) => `The first part of the emergency fund: ${a ? months(a.starter_reserve_months) : "one month"} of living costs, saved before anything optional.`,
  },
  "small-reserve": {
    title: "Small reserve",
    text: (a) => `A minimum cash buffer ARM always protects first: ${a ? `the lesser of ${money(a.critical_reserve_cap_cents)} or one month` : "a small amount"} of living costs.`,
  },
  "high-interest-debt": {
    title: "High-interest debt",
    text: (a) => `Debt charging ${a ? `${percent(a.high_interest_apr_threshold)} APR or more` : "a high interest rate"}, such as most credit cards. Paying it early usually beats what the same money could earn invested.`,
  },
  apr: {
    title: "APR",
    text: () => "Annual percentage rate: what borrowing costs you per year, as a percentage of what you owe.",
  },
  "employer-match": {
    title: "Employer match",
    text: () => "Money your employer adds to your retirement account when you contribute, up to a limit. ARM keeps you at the full match whenever you can afford it.",
  },
  "target-date-fund": {
    title: "Target-date fund",
    text: () => "One fund built around the year you plan to retire. It holds stocks and bonds and shifts gradually toward bonds as that year approaches.",
  },
  "glide-path": {
    title: "Glide path",
    text: (a) => {
      const g = a?.glide_path;
      if (!g?.length) return "The schedule a target-date fund follows to move from stocks toward bonds over time.";
      const sorted = [...g].sort((x, y) => y.years_to_retirement - x.years_to_retirement);
      const far = sorted[0], near = sorted[sorted.length - 1];
      return `The schedule a target-date fund follows to move from stocks toward bonds. In this model: ${percent(far.equity_weight)} stocks ${far.years_to_retirement} years out, ${percent(near.equity_weight)} at retirement.`;
    },
  },
  "current-habits": {
    title: "Current habits",
    text: () => "What happens if you keep saving and paying exactly as you do today. It's the baseline every plan is compared with.",
  },
  "todays-dollars": {
    title: "Today's dollars",
    text: (a) => `A future amount adjusted for inflation${a ? ` (${percent(a.annual_inflation)} a year here)` : ""}, so you can compare it with what things cost now.`,
  },
  projection: {
    title: "Projection",
    text: () => "An estimate of balances month by month using fixed, illustrative assumptions. Real markets rise and fall; this isn't a forecast or a guarantee.",
  },
  "compound-growth": {
    title: "Compound growth",
    text: () => "Earning returns on your earlier returns. The longer money stays invested, the more of its growth comes from growth itself.",
  },
};
