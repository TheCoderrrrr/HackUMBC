/**
 * Frontend ↔ backend sync checks on real engine output: the contract examples (kept current by
 * backend/tests/test_contracts.py) and the saved offline bundle.
 */
import { describe, expect, it } from "vitest";
import type { Evaluation, FinancialProfile } from "../api/types";
import { firstReach, gapAt } from "./chart";
import { balanceAtYear, yearlyBalances } from "./display";

const examples = import.meta.glob("../../../contracts/examples/evaluate-{jordan,morgan,casey}.response.json", {
  eager: true, import: "default",
}) as Record<string, Evaluation>;
const bundle = import.meta.glob("../../../ios/AdaptiveRetirement/Resources/Demo/*-original.json", {
  eager: true, import: "default",
}) as Record<string, { evaluation: Evaluation }>;
const profiles = (Object.values(import.meta.glob("../../../contracts/examples/demo-profiles.response.json", {
  eager: true, import: "default",
}))[0] as { profiles: FinancialProfile[] }).profiles;

const evaluations: [string, Evaluation][] = [
  ...Object.entries(examples),
  ...Object.entries(bundle).map(([k, v]) => [k, v.evaluation] as [string, Evaluation]),
];

describe.each(evaluations)("%s", (_, evaluation) => {
  const profile = profiles.find((p) => p.id === evaluation.profile_id)!;
  const years = profile.retirement_age - profile.age;

  it("is a real, known profile", () => {
    expect(profile).toBeDefined();
    expect(evaluations.length).toBeGreaterThanOrEqual(6);
  });

  for (const strategy of ["current", "adaptive"] as const) {
    it(`${strategy}: yearly values are the engine points at months 0, 12, 24, … (the backend's rule)`, () => {
      const points = evaluation.projections[strategy].points;
      const engineYearly = points.filter((p) => p.month % 12 === 0).map((p) => p.retirement_balance_cents);
      expect(yearlyBalances(evaluation.projections[strategy], years)).toEqual(engineYearly.slice(0, years + 1));
    });

    it(`${strategy}: the chart ends on the retirement figure shown above it`, () => {
      const projection = evaluation.projections[strategy];
      expect(balanceAtYear(projection, years)).toBe(projection.retirement_balance_nominal_cents);
    });
  }

  it("the chart starts at today's balance", () => {
    expect(yearlyBalances(evaluation.projections.adaptive, years)[0]).toBe(profile.retirement_balance_cents);
  });

  it("the gap at retirement matches the two engine totals", () => {
    const plan = yearlyBalances(evaluation.projections.adaptive, years);
    const habits = yearlyBalances(evaluation.projections.current, years);
    expect(gapAt(plan, habits, years)).toBe(
      evaluation.projections.adaptive.retirement_balance_nominal_cents! - evaluation.projections.current.retirement_balance_nominal_cents!,
    );
  });

  it("a goal equal to the final balance is reached exactly at retirement (values only grow)", () => {
    const plan = yearlyBalances(evaluation.projections.adaptive, years);
    expect(plan.every((v, i) => i === 0 || v >= plan[i - 1])).toBe(true);
    expect(firstReach(plan, plan[years])).toBe(plan.indexOf(plan[years]));
  });
});
