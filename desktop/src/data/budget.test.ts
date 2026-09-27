/** "This month" must add up, on real engine output. */
import { describe, expect, it } from "vitest";
import type { Evaluation, FinancialProfile } from "../api/types";
import { budgetSlices, buildDisplay, monthBudget } from "./display";

const examples = import.meta.glob("../../../contracts/examples/evaluate-{jordan,morgan,casey}.response.json", { eager: true, import: "default" }) as Record<string, Evaluation>;
const bundle = import.meta.glob("../../../ios/AdaptiveRetirement/Resources/Demo/*.json", { eager: true, import: "default" }) as Record<string, { evaluation?: Evaluation }>;
const profiles = (Object.values(import.meta.glob("../../../contracts/examples/demo-profiles.response.json", { eager: true, import: "default" }))[0] as { profiles: FinancialProfile[] }).profiles;

const cases: [string, Evaluation][] = [
  ...Object.entries(examples),
  ...Object.entries(bundle).filter(([, v]) => v.evaluation && profiles.some((p) => p.id === v.evaluation!.profile_id))
    .map(([k, v]) => [k, v.evaluation!] as [string, Evaluation]),
];

describe.each(cases)("%s", (_, evaluation) => {
  const profile = profiles.find((p) => p.id === evaluation.profile_id)!;
  const b = monthBudget(buildDisplay(profile, evaluation, "saved"));

  it("money to plan with = take-home pay + the current contribution's after-tax cost", () => {
    expect(b.takeHomeCents + b.currentContributionCents).toBe(b.toPlanCents);
  });
  it("every line adds up to exactly the money to plan with", () => {
    expect(b.totalCents).toBe(b.toPlanCents);
  });
  it("the Getting started pie covers every funded line once and closes the circle", () => {
    const slices = budgetSlices(b.lines);
    expect(slices.map((s) => s.key)).toEqual(b.lines.filter((l) => l.cents > 0).map((l) => l.key));
    expect(slices.reduce((s, x) => s + x.cents, 0)).toBe(b.totalCents);
    expect(slices.reduce((s, x) => s + x.share, 0)).toBeCloseTo(1, 12);
    expect(slices[0].start).toBe(0);
    expect(slices[slices.length - 1].end).toBe(1);
    slices.slice(1).forEach((s, i) => expect(s.start).toBeCloseTo(slices[i].end, 12));
  });
  it("no line is negative", () => {
    expect(b.lines.every((l) => l.cents >= 0)).toBe(true);
  });
});

it("covers every saved demo result", () => expect(cases.length).toBeGreaterThanOrEqual(12));
