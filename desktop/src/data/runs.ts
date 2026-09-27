import type { PlanningPreference, RunSummary, Scenario } from "../api/types";
import { percent } from "./format";
import { STYLE_INFO } from "./styles";

/** "Retire at 69 · adaptive contribution · Balanced": the choices a run was saved with. */
export function runChoices(run: RunSummary): string {
  const rate = run.scenario?.employee_contribution_rate;
  const parts = [`Retire at ${run.retirement_age}`, rate === null || rate === undefined ? "adaptive contribution" : `${percent(rate)} fixed`];
  if (run.planning_preference) parts.push(STYLE_INFO[run.planning_preference].label);
  return parts.join(" · ");
}

/**
 * What opening a saved run puts back: its plan style (null = keep the current one, for runs saved
 * before styles were recorded) and its scenario. A run saved without a scenario is the plan itself,
 * so it restores the plan's own retirement age with the adaptive contribution.
 */
export function restoreRun(run: RunSummary, planRetirementAge: number): { style: PlanningPreference | null; scenario: Scenario } {
  return {
    style: run.planning_preference ?? null,
    scenario: run.scenario ?? { retirement_age: planRetirementAge, employee_contribution_rate: null },
  };
}
