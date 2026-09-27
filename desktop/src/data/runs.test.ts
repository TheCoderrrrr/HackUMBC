import { describe, expect, it } from "vitest";
import type { RunSummary } from "../api/types";
import { bestInRow, shortName, weightedScore } from "./fundView";
import { restoreRun, runChoices } from "./runs";

const run = (over: Partial<RunSummary>): RunSummary => ({
  run_id: "r1", profile_id: "morgan", label: "x", created_at: "2026-09-27T12:00:00Z", as_of_date: "2026-09-01",
  scenario: null, primary_strategy: "adaptive", retirement_age: 67, final_retirement_balance_cents: 1, decision_source: "rules_fallback",
  model_id: null, prompt_version: "p", model_version: "m", policy_version: "v", input_hash: "h", ...over,
});

describe("opening a saved run", () => {
  it("restores the scenario and plan style it was saved with", () => {
    const saved = run({ scenario: { retirement_age: 69, employee_contribution_rate: 0.08 }, planning_preference: "debt_reduction", retirement_age: 69 });
    expect(restoreRun(saved, 67)).toEqual({ style: "debt_reduction", scenario: { retirement_age: 69, employee_contribution_rate: 0.08 } });
    expect(runChoices(saved)).toBe("Retire at 69 · 8% fixed · Debt payoff first");
  });

  it("a run saved without a scenario reopens as the plan itself", () => {
    const saved = run({ planning_preference: "cash_security" });
    expect(restoreRun(saved, 67)).toEqual({ style: "cash_security", scenario: { retirement_age: 67, employee_contribution_rate: null } });
    expect(runChoices(saved)).toBe("Retire at 67 · adaptive contribution · Cash security first");
  });

  it("older runs without a recorded style keep the current style", () => {
    expect(restoreRun(run({}), 67).style).toBeNull();
    expect(runChoices(run({}))).toBe("Retire at 67 · adaptive contribution");
  });
});

describe("fund shortlist helpers", () => {
  it("marks the best value only when funds differ", () => {
    expect(bestInRow([0.0009, 0.0012, 0.0009], true)).toBe(0.0009);
    expect(bestInRow([0.2, 0.25, undefined])).toBe(0.25);
    expect(bestInRow([0.0009, 0.0009, 0.0009], true)).toBeUndefined();
    expect(bestInRow([0.1, undefined])).toBeUndefined();
  });

  it("score is the weighted sum of its parts", () => {
    const parts = { horizon_fit: 0.85, risk_fit: 0.396, fee_fit: 0.91, data_completeness: 0.95 };
    const weights = { horizon_fit: 0.4, risk_fit: 0.3, fee_fit: 0.2, data_completeness: 0.1 };
    expect(weightedScore(parts, weights)).toBeCloseTo(0.7358, 10);
  });

  it("short names drop the class and 'Fund'", () => {
    expect(shortName("State Street Target Retirement 2055 Fund, Class K")).toBe("State Street Target Retirement 2055");
    expect(shortName("BlackRock LifePath Index 2060 Fund, Class K")).toBe("BlackRock LifePath Index 2060");
  });
});
