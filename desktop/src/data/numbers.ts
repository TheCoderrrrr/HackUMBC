import type { DebtInput, FinancialProfile, ProfileInput } from "../api/types";

/** What the form holds: plain strings as typed, in dollars and percents. */
export interface NumbersForm {
  name: string;
  age: string;
  retirementAge: string;
  salary: string;        // $ per year, before tax
  takeHome: string;      // $ per month, after tax
  living: string;        // $ per month
  contribution: string;  // % of pay
  retirementBalance: string;
  fundID: string;
  fundAccountType: "401k" | "ira";
  fundBalanceConfirmed: boolean;
  fundInPlanMenu: boolean;
  emergencyCash: string;
  matchKind: "match" | "none" | "unknown";
  matchUpTo: string;     // % of pay the employer matches up to
  matchRate: string;     // % of each dollar the employer adds (100 = dollar for dollar)
  debts: { type: DebtInput["type"]; balance: string; apr: string; minimum: string }[];
}

export const EMPTY_FORM: NumbersForm = {
  name: "", age: "", retirementAge: "67", salary: "", takeHome: "", living: "", contribution: "", retirementBalance: "",
  emergencyCash: "", matchKind: "match", matchUpTo: "", matchRate: "100", debts: [],
  fundID: "", fundAccountType: "401k", fundBalanceConfirmed: false, fundInPlanMenu: false,
};

/** Typed amounts: "$84,000", "84000", "4.8k" → a number; blank or invalid → null. */
export function parseAmount(text: string): number | null {
  const t = text.trim().toLowerCase().replace(/[$,\s%]/g, "");
  const m = /^(\d+(?:\.\d+)?)(k?)$/.exec(t);
  if (!m) return null;
  return Number(m[1]) * (m[2] === "k" ? 1000 : 1);
}

const cents = (dollars: number) => Math.round(dollars * 100);
const rate = (percent: number) => Math.round(percent * 100) / 10000; // 5 → 0.05, 12.5 → 0.125

/**
 * Converts the form to the API's ProfileInput (cents and decimal rates). Returns the input, or
 * the form fields that still need a value. The server validates everything else and says which
 * field is wrong.
 */
export function formToInput(form: NumbersForm): { input: ProfileInput | null; missing: string[] } {
  const missing: string[] = [];
  const need = (field: keyof NumbersForm, value: string) => {
    const n = parseAmount(value);
    if (n === null) missing.push(field);
    return n ?? 0;
  };
  const age = need("age", form.age);
  const retirementAge = need("retirementAge", form.retirementAge);
  const salary = need("salary", form.salary);
  const takeHome = need("takeHome", form.takeHome);
  const living = need("living", form.living);
  const contribution = need("contribution", form.contribution);
  const retirementBalance = need("retirementBalance", form.retirementBalance);
  const emergencyCash = need("emergencyCash", form.emergencyCash);
  const upTo = form.matchKind === "match" ? need("matchUpTo", form.matchUpTo) : 0;
  const matchRate = form.matchKind === "match" ? need("matchRate", form.matchRate) : 0;
  const debts: DebtInput[] = form.debts.map((d, i) => ({
    type: d.type,
    balance_cents: cents(need(`debts.${i}.balance` as keyof NumbersForm, d.balance)),
    apr: rate(need(`debts.${i}.apr` as keyof NumbersForm, d.apr)),
    minimum_payment_cents: cents(need(`debts.${i}.minimum` as keyof NumbersForm, d.minimum)),
  }));
  if (missing.length) return { input: null, missing };
  return {
    missing,
    input: {
      name: form.name.trim() || "You",
      age: Math.round(age),
      retirement_age: Math.round(retirementAge),
      annual_gross_salary_cents: cents(salary),
      monthly_take_home_cents: cents(takeHome),
      monthly_living_expenses_cents: cents(living),
      employee_contribution_rate: rate(contribution),
      retirement_balance_cents: cents(retirementBalance),
      fund_id: form.fundID || null,
      fund_account_type: form.fundID ? form.fundAccountType : null,
      fund_balance_confirmed: Boolean(form.fundID && form.fundBalanceConfirmed),
      plan_menu_fund_ids: form.fundID && form.fundAccountType === "401k" && form.fundInPlanMenu ? [form.fundID] : null,
      emergency_cash_cents: cents(emergencyCash),
      match: form.matchKind === "match"
        ? { kind: "match", up_to_rate: rate(upTo), match_per_dollar: matchRate / 100 }
        : { kind: form.matchKind },
      debts,
    },
  };
}

const dollars = (c: number) => String(Math.round(c) / 100);
const percent = (r: number) => String(Math.round(r * 10000) / 100);

/** The reverse: a stored ProfileInput back into form strings (for editing). */
export function inputToForm(input: ProfileInput): NumbersForm {
  return {
    name: input.name && input.name !== "You" ? input.name : "",
    age: String(input.age),
    retirementAge: String(input.retirement_age),
    salary: dollars(input.annual_gross_salary_cents),
    takeHome: dollars(input.monthly_take_home_cents),
    living: dollars(input.monthly_living_expenses_cents),
    contribution: percent(input.employee_contribution_rate),
    retirementBalance: dollars(input.retirement_balance_cents),
    fundID: input.fund_id ?? "",
    fundAccountType: input.fund_account_type ?? "401k",
    fundBalanceConfirmed: input.fund_balance_confirmed ?? false,
    fundInPlanMenu: Boolean(input.plan_menu_fund_ids?.includes(input.fund_id ?? "")),
    emergencyCash: dollars(input.emergency_cash_cents),
    matchKind: input.match.kind,
    matchUpTo: input.match.up_to_rate ? percent(input.match.up_to_rate) : "",
    matchRate: input.match.match_per_dollar ? String(Math.round(input.match.match_per_dollar * 100)) : "100",
    debts: (input.debts ?? []).map((d) => ({ type: d.type, balance: dollars(d.balance_cents), apr: percent(d.apr), minimum: dollars(d.minimum_payment_cents) })),
  };
}

/** A demo profile as a starting form ("Start from Morgan's numbers"). */
export function profileToForm(p: FinancialProfile): NumbersForm {
  const tier = p.employer_match.tiers[0];
  return inputToForm({
    name: "", age: p.age, retirement_age: p.retirement_age,
    annual_gross_salary_cents: p.annual_gross_salary_cents, monthly_take_home_cents: p.monthly_take_home_cents,
    monthly_living_expenses_cents: p.monthly_living_expenses_cents, employee_contribution_rate: p.employee_contribution_rate,
    retirement_balance_cents: p.retirement_balance_cents, emergency_cash_cents: p.emergency_cash_cents,
    fund_id: p.fund_id, fund_balance_confirmed: p.fund_balance_confirmed,
    fund_account_type: p.fund_account_type, plan_menu_fund_ids: p.plan_menu_fund_ids,
    match: p.employer_match.status === "confirmed" && tier
      ? { kind: "match", up_to_rate: tier.employee_rate_to, match_per_dollar: tier.match_per_employee_dollar }
      : { kind: p.employer_match.status === "none" ? "none" : "unknown" },
    debts: p.debts.map((d) => ({ type: d.type as DebtInput["type"], balance_cents: d.balance_cents, apr: d.apr, minimum_payment_cents: d.minimum_payment_cents })),
  });
}

/** Server field paths (from a 422) → the form field to highlight. */
export function formFieldFor(path: string): string {
  const map: Record<string, string> = {
    age: "age", retirement_age: "retirementAge", annual_gross_salary_cents: "salary",
    monthly_take_home_cents: "takeHome", monthly_living_expenses_cents: "living",
    employee_contribution_rate: "contribution", retirement_balance_cents: "retirementBalance",
    emergency_cash_cents: "emergencyCash", match: "matchUpTo", name: "name",
  };
  const debt = /^debts\.(\d+)\.(\w+)/.exec(path);
  if (debt) {
    const f = { balance_cents: "balance", apr: "apr", minimum_payment_cents: "minimum" }[debt[2]] ?? "balance";
    return `debts.${debt[1]}.${f}`;
  }
  return map[path.split(".")[0]] ?? path;
}
