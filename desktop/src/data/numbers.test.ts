import { describe, expect, it } from "vitest";
import type { FinancialProfile } from "../api/types";
import { EMPTY_FORM, formFieldFor, formToInput, inputToForm, parseAmount, profileToForm } from "./numbers";
import { newProfileKey } from "./profileKey";

const profiles = (Object.values(import.meta.glob("../../../contracts/examples/demo-profiles.response.json", {
  eager: true, import: "default",
}))[0] as { profiles: FinancialProfile[] }).profiles;
const morgan = profiles.find((p) => p.id === "morgan")!;

describe("parseAmount", () => {
  it.each([["84000", 84000], ["$84,000", 84000], ["4.8k", 4800], [" 12.5% ", 12.5], ["0", 0]])("%s", (t, n) =>
    expect(parseAmount(t)).toBe(n));
  it.each(["", "abc", "-5", "1e5", "5..2"])("rejects %s", (t) => expect(parseAmount(t)).toBeNull());
});

describe("form ↔ API input", () => {
  it("Morgan's profile → form → input gives back Morgan's exact numbers (what the backend rebuilds)", () => {
    const { input, missing } = formToInput(profileToForm(morgan));
    expect(missing).toEqual([]);
    expect(input).toMatchObject({
      age: morgan.age, retirement_age: morgan.retirement_age,
      annual_gross_salary_cents: morgan.annual_gross_salary_cents, monthly_take_home_cents: morgan.monthly_take_home_cents,
      monthly_living_expenses_cents: morgan.monthly_living_expenses_cents, employee_contribution_rate: morgan.employee_contribution_rate,
      retirement_balance_cents: morgan.retirement_balance_cents, emergency_cash_cents: morgan.emergency_cash_cents,
      match: { kind: "match", up_to_rate: morgan.employer_match.tiers[0].employee_rate_to, match_per_dollar: morgan.employer_match.tiers[0].match_per_employee_dollar },
    });
    expect(input!.debts).toEqual(morgan.debts.map(({ type, balance_cents, apr, minimum_payment_cents }) => ({ type, balance_cents, apr, minimum_payment_cents })));
  });

  it("round-trips a stored input for editing", () => {
    const { input } = formToInput(profileToForm(morgan));
    expect(formToInput(inputToForm(input!)).input).toEqual(input);
  });

  it("keeps fractional percents exact", () => {
    const { input } = formToInput({ ...profileToForm(morgan), contribution: "12.5", matchUpTo: "6", matchRate: "50" });
    expect(input!.employee_contribution_rate).toBe(0.125);
    expect(input!.match).toEqual({ kind: "match", up_to_rate: 0.06, match_per_dollar: 0.5 });
  });

  it("lists every field still missing, and skips match fields when there is no match", () => {
    expect(formToInput(EMPTY_FORM).missing).toEqual(
      ["age", "salary", "takeHome", "living", "contribution", "retirementBalance", "emergencyCash", "matchUpTo"]);
    expect(formToInput({ ...EMPTY_FORM, matchKind: "none" }).missing).not.toContain("matchUpTo");
  });

  it("maps server error paths to form fields", () => {
    expect(formFieldFor("monthly_take_home_cents")).toBe("takeHome");
    expect(formFieldFor("debts.0.minimum_payment_cents")).toBe("debts.0.minimum");
    expect(formFieldFor("match")).toBe("matchUpTo");
  });
});

describe("profile key", () => {
  it("is 43 base64url characters, the format the backend accepts, and unique", () => {
    const keys = new Set(Array.from({ length: 200 }, newProfileKey));
    expect(keys.size).toBe(200);
    for (const k of keys) expect(k).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});
