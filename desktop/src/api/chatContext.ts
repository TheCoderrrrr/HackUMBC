import type { Display, DataMode } from "../data/display";
import { money, percent } from "../data/format";
import type { Tab } from "../store";

export type ScreenFact = { label: string; value: string };
export type ScreenContext = {
  screen: Tab;
  data_mode: DataMode | "not_loaded";
  facts: ScreenFact[];
};

/** Facts already shown in the app, not raw account records or hidden calculation inputs. */
export function screenContext(tab: Tab, display: Display | null, mode: DataMode, extra: ScreenFact[] = []): ScreenContext {
  if (!display) return { screen: tab, data_mode: "not_loaded", facts: extra.slice(0, 40) };
  const base: ScreenFact[] = [
    { label: "customer", value: display.profile.name },
    { label: "as_of_date", value: display.profile.as_of_date },
    { label: "current_age", value: String(display.profile.age) },
    { label: "planned_retirement_age", value: String(display.profile.retirement_age) },
  ];
  if (tab === "overview" || tab === "plan" || tab === "explore") {
    base.push(
      { label: "retirement_savings", value: money(display.profile.retirement_balance_cents) },
      { label: "employee_monthly_contribution", value: money(display.employeeCents) },
      { label: "employee_contribution_rate", value: percent(display.rate) },
      { label: "employer_monthly_match", value: display.employerCents === null ? "unknown" : money(display.employerCents) },
      { label: "emergency_savings", value: money(display.profile.emergency_cash_cents) },
      { label: "emergency_months", value: display.emergencyMonths.toFixed(1) },
      { label: "next_step", value: display.nextStep.headline.slice(0, 120) },
      { label: "next_step_monthly_amount", value: display.nextStep.amountCents === null ? "not shown" : money(display.nextStep.amountCents) },
      { label: "next_step_detail", value: display.nextStep.detail.slice(0, 120) },
      { label: "employer_match_captured", value: String(display.matchCaptured) },
      { label: "plan_source", value: display.origin.slice(0, 120) },
    );
    const current = display.evaluation.projections.current.retirement_balance_today_cents;
    const adaptive = display.evaluation.projections.adaptive.retirement_balance_today_cents;
    if (current !== null) base.push({ label: "current_projected_retirement_balance", value: money(current) });
    if (adaptive !== null) base.push({ label: "adaptive_projected_retirement_balance", value: money(adaptive) });
  }
  if (tab === "plan") {
    base.push(
      { label: "stock_allocation", value: percent(display.equityWeight) },
      { label: "starter_reserve_target", value: money(display.starterTargetCents) },
      { label: "full_reserve_target", value: money(display.fullTargetCents) },
      ...display.cash.map((item): ScreenFact => ({ label: `monthly_${item.kind}_priority`, value: money(item.amountCents) })),
      ...display.debts.slice(0, 3).flatMap((debt, index): ScreenFact[] => [
        { label: `debt_${index + 1}_type`, value: debt.name },
        { label: `debt_${index + 1}_balance`, value: money(debt.balanceCents) },
        { label: `debt_${index + 1}_apr`, value: percent(debt.apr) },
        { label: `debt_${index + 1}_monthly_extra`, value: money(debt.extraCents) },
      ]),
    );
  }
  return { screen: tab, data_mode: mode, facts: [...base, ...extra].slice(0, 40) };
}
