import { useEffect, useMemo, useRef, useState } from "react";
import { errorMessage } from "../api/client";
import type { ScreenFact } from "../api/chatContext";
import type { Evaluation, PlanningPreference, Projection, RunSummary, Scenario } from "../api/types";
import { parseAmount } from "../data/numbers";
import { Icon, Stepper } from "../components/ui";
import { LineChart, type Series } from "../components/LineChart";
import { pointAtMonth, yearlyBalances, type Display } from "../data/display";
import { money, monthLabel, percent } from "../data/format";
import type { Preset } from "../data/saved";
import { useStore } from "../store";
import { Tabs } from "../components/Tabs";

type ExploreView = "compare" | "timeline" | "saved";
import { History, type Shown } from "./History";
import { restoreRun, runChoices } from "../data/runs";

type Policy = "adaptive" | "fixed";
interface Draft {
  retirementAge: number;
  policy: Policy;
  /** Percent, 0–20 in 0.5 steps. */
  fixedRate: number;
  extraDebt: string;
  priorityStyle: PlanningPreference | "same";
  preset: Preset | null;
}

export const original = (d: Display): Draft => ({
  retirementAge: d.profile.retirement_age,
  policy: "adaptive",
  fixedRate: d.currentRate * 100,
  extraDebt: "",
  priorityStyle: "same",
  preset: "original",
});
const sameDraft = (a: Draft, b: Draft) =>
  a.retirementAge === b.retirementAge && a.policy === b.policy && (a.policy === "adaptive" || a.fixedRate === b.fixedRate)
  && a.extraDebt === b.extraDebt && a.priorityStyle === b.priorityStyle;

const SECONDS_PER_MONTH = 0.11;

export function Explore({ display, onContext }: { display: Display; onContext: (facts: ScreenFact[]) => void }) {
  const { profile, evaluation } = display;
  const { setDrawer, style, setStyle, setPendingScenario, load } = useStore();
  const [compared, setCompared] = useState<Shown | null>(null);
  const [view, setView] = useState<ExploreView>("compare");
  // A saved run the person opened: its plan style and scenario are restored and recalculated.
  const [opened, setOpened] = useState<RunSummary | null>(null);
  const openRun = (run: RunSummary) => {
    const restored = restoreRun(run, profile.retirement_age);
    setOpened(run);
    if (restored.style && restored.style !== style) setStyle(restored.style);
    setPendingScenario(restored.scenario);
    setView("compare");
  };
  // The reopened result: the scenario's evaluation, or the plan itself for a run saved without one.
  const reopened = !opened ? null
    : opened.scenario ? compared?.evaluation ?? null
      : load.status === "loading" ? null : evaluation;
  const custom = compared?.evaluation ?? null;
  useEffect(() => () => onContext([]), [onContext]);
  useEffect(() => {
    const facts: ScreenFact[] = [
      { label: "explore_view", value: view },
      { label: "current_projected_retirement_balance", value: display.evaluation.projections.current.retirement_balance_today_cents === null ? "not available" : money(display.evaluation.projections.current.retirement_balance_today_cents) },
      { label: "adaptive_projected_retirement_balance", value: display.evaluation.projections.adaptive.retirement_balance_today_cents === null ? "not available" : money(display.evaluation.projections.adaptive.retirement_balance_today_cents) },
      { label: "projection_kind", value: "illustrative scenario, not a forecast" },
    ];
    if (compared) facts.push(
      { label: "compared_retirement_age", value: String(compared.scenario?.retirement_age ?? compared.evaluation.projections.adaptive.retirement_age) },
      { label: "compared_contribution_rate", value: compared.scenario?.employee_contribution_rate === null || compared.scenario?.employee_contribution_rate === undefined ? "adaptive policy" : percent(compared.scenario.employee_contribution_rate) },
      { label: "compared_feasible", value: String(compared.evaluation.projections.custom?.feasible ?? true) },
      { label: "compared_projected_retirement_balance", value: compared.evaluation.projections.custom?.retirement_balance_today_cents === null || compared.evaluation.projections.custom?.retirement_balance_today_cents === undefined ? "not available" : money(compared.evaluation.projections.custom.retirement_balance_today_cents) },
    );
    onContext(facts);
  }, [view, compared, display, onContext]);
  // A new scenario result is what the person wants to see next.
  const onResult = (shown: Shown | null) => {
    setCompared(shown);
    if (shown) setView("compare");
  };
  const feasible = custom?.projections.custom?.feasible;

  return (
    <div className="grid explore fade-in" key={profile.id}>
      <div className="section explore-tabs">
        <Tabs label="Explore views" value={view} onChange={setView} items={[
          { id: "compare", label: "Compare", hint: compared ? (feasible === false ? "Can't be funded" : "With your scenario") : "Plan vs current habits" },
          { id: "timeline", label: "Timeline", hint: "Next five years" },
          { id: "saved", label: "Saved runs", hint: "Tiger Data history" },
        ]}>
          {view === "compare" && (
            <div className="stack" style={{ gap: 20 }}>
              {opened && (
                <div className="opened-run fade-in" role="status">
                  <Icon name="replay" size={15} />
                  <span>
                    <b>{runChoices(opened)}</b>
                    <span className="caption">
                      {" · "}{!reopened ? "Recalculating…"
                        : reopened.input_hash === opened.input_hash ? "Same inputs as when you saved it, so the numbers match."
                          : "Recalculated with the current numbers; results can differ from when it was saved."}
                    </span>
                  </span>
                  <button className="close small" onClick={() => setOpened(null)} aria-label="Close saved run"><Icon name="close" size={12} /></button>
                </div>
              )}
              <Comparison display={display} custom={custom?.projections.custom ?? null} />
              <Outcomes evaluation={evaluation} custom={custom?.projections.custom ?? null} asOf={profile.as_of_date} />
              <FundAndRules evaluation={custom ?? evaluation} />
            </div>
          )}
          {view === "timeline" && <Timeline display={display} />}
          {view === "saved" && <History shown={compared ?? { evaluation, scenario: null }} onOpen={openRun} openedID={opened?.run_id ?? null} />}
        </Tabs>
      </div>
      <div className="stack" style={{ position: "sticky", top: 84 }}>
        <ScenarioControls display={display} onResult={onResult} onEdit={() => setOpened(null)} />
        <button className="link" style={{ display: "inline-flex", gap: 8, alignItems: "center", fontSize: 15, alignSelf: "flex-start" }}
          onClick={() => setDrawer("assumptions")}>
          <Icon name="sliders" size={16} /> Modeling assumptions
        </button>
      </div>
    </div>
  );
}

function FundAndRules({ evaluation }: { evaluation: Evaluation }) {
  const fund = evaluation.assumptions.fund_model;
  const comparison = evaluation.rules_comparison;
  return <section className="section">
    <h2 className="h-section">What drives this plan</h2>
    <p className="body" style={{ marginTop: 8 }}>
      {fund ? <>{fund.fund_name} · target {fund.target_year} · modeled expense {percent(fund.applied_expense_ratio)}.
        The {fund.glide_path_mode === "documented" ? "issuer's documented" : "generic fallback"} glide path sets the modeled stock mix.</>
        : "No fund is selected. Projections use a generic retirement-age glide path."}
    </p>
    {fund && <p className="caption" style={{ marginTop: 8 }}>
      <a href={fund.glide_path_source_url} target="_blank" rel="noreferrer">Glide path source</a> ·{" "}
      <a href={fund.fee_source_url} target="_blank" rel="noreferrer">Fee source</a> · Catalog {fund.catalog_version}
      {fund.limitation && <> · {fund.limitation}</>}
    </p>}
    {comparison && <details style={{ marginTop: 18 }}>
      <summary>AI decision compared with default rules</summary>
      <p className="body" style={{ marginTop: 10 }}>
        {evaluation.decision_summary.source === "ai" ? "AI chose" : "Default rules chose"} {comparison.ai_priorities.join(" → ")};
        default rules choose {comparison.rules_priorities.join(" → ")}.
        {comparison.difference_cents === null ? " The outcome could not be compared." : comparison.outcome === "equal"
          ? " The projected retirement balance is the same."
          : ` The projected retirement balance is ${money(Math.abs(comparison.difference_cents))} ${comparison.outcome} than default rules.`}
      </p>
      <p className="caption">The comparison changes the decision order only. Fund, cash flow, and return assumptions are held fixed.</p>
    </details>}
  </section>;
}

// ---------- Timeline ----------

function Timeline({ display }: { display: Display }) {
  const { profile, evaluation } = display;
  const adaptive = evaluation.projections.adaptive;
  const current = evaluation.projections.current;
  const last = Math.min(60, evaluation.financial_state.months_until_retirement);
  const [month, setMonth] = useState(0);
  const [playing, setPlaying] = useState(false);
  const frame = useRef(0);

  useEffect(() => {
    if (!playing) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) {
      setMonth(last);
      setPlaying(false);
      return;
    }
    const startMonth = month >= last ? 0 : month;
    const start = performance.now();
    const tick = (now: number) => {
      const next = Math.min(startMonth + (now - start) / 1000 / SECONDS_PER_MONTH, last);
      setMonth(next);
      if (next >= last) setPlaying(false);
      else frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame.current);
  }, [playing, last]);

  const m = Math.round(month);
  const milestones = [
    { month: adaptive.debt_free_month, title: "Debt-free", icon: "seal" },
    { month: adaptive.starter_reserve_month, title: "One-month cushion", icon: "umbrella" },
    { month: adaptive.full_reserve_month, title: "Emergency fund full", icon: "flag" },
  ].filter((x): x is { month: number; title: string; icon: string } => x.month !== null && x.month > 0 && x.month <= last);

  const context = (() => {
    if (m === 0) return "Opening month";
    const exact = milestones.find((x) => x.month === m);
    if (exact) return exact.title;
    if (adaptive.debt_free_month !== null && m < adaptive.debt_free_month) return "Paying down debt";
    if (adaptive.full_reserve_month !== null && m < adaptive.full_reserve_month) return "Building reserves";
    return "Saving for retirement";
  })();

  const a = pointAtMonth(adaptive, m);
  const c = pointAtMonth(current, m);
  const inWindow = (p: Projection) => p.points.filter((x) => x.month <= last);
  const peak = (key: "retirement_balance_cents" | "cash_cents" | "debt_cents") =>
    Math.max(...inWindow(adaptive).map((x) => x[key]), ...inWindow(current).map((x) => x[key]), 1);

  const rows = [
    { title: "Retirement", key: "retirement_balance_cents" as const },
    { title: "Emergency cash", key: "cash_cents" as const },
    { title: "Debt", key: "debt_cents" as const },
  ];

  return (
    <section className="glass card">
      <h2 className="h-section">The next five years</h2>
      <p className="subtitle" style={{ marginBottom: 16 }}>Press play, or drag to any month.</p>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div>
          <div className="num" style={{ fontSize: 28, fontWeight: 500, letterSpacing: -0.6 }}>{monthLabel(profile.as_of_date, m)}</div>
          <div className="label" style={{ fontSize: 13, marginTop: 2 }}>{context}</div>
        </div>
        <button className="close" style={{ color: "var(--accent)" }} onClick={() => setPlaying((p) => !p)}
          aria-label={playing ? "Pause" : m >= last ? "Replay" : "Play the timeline"}>
          <Icon name={playing ? "pause" : m >= last ? "replay" : "play"} size={16} />
        </button>
      </div>

      <input className="range" type="range" min={0} max={last} step={1} value={m}
        style={{ ["--fill" as string]: `${(m / last) * 100}%`, marginTop: 14 }}
        onChange={(e) => { setPlaying(false); setMonth(Number(e.target.value)); }}
        aria-label="Timeline month" aria-valuetext={monthLabel(profile.as_of_date, m)} />
      <div className="axis" style={{ marginTop: 0 }}>
        <span>{monthLabel(profile.as_of_date, 0)}</span>
        <span>{monthLabel(profile.as_of_date, last)}</span>
      </div>

      <div style={{ display: "grid", gap: 16, marginTop: 22 }}>
        {rows.map((r) => (
          <div key={r.key}>
            <div className="row" style={{ minHeight: 0, marginBottom: 7 }}>
              <span className="title" style={{ fontSize: 14 }}>{r.title}</span>
              <span className="caption num">
                <span style={{ color: "var(--accent)", fontWeight: 500 }}>{money(a?.[r.key] ?? 0)}</span>
                <span style={{ margin: "0 6px" }}>vs</span>
                <span style={{ color: "var(--blue)" }}>{money(c?.[r.key] ?? 0)}</span>
              </span>
            </div>
            <Bar value={a?.[r.key] ?? 0} max={peak(r.key)} color="linear-gradient(90deg,#47853d,#a8e6a1)" />
            <Bar value={c?.[r.key] ?? 0} max={peak(r.key)} color="linear-gradient(90deg,#2f5a96,#8fb8f5)" thin />
          </div>
        ))}
      </div>

      <div style={{ display: "flex", gap: 12, marginTop: 22, flexWrap: "wrap" }}>
        {milestones.length === 0 && <span className="caption">No plan milestones in this window.</span>}
        {milestones.map((x) => (
          <button key={x.title} className={`pill ${m === x.month ? "selected" : "neutral"}`}
            onClick={() => { setPlaying(false); setMonth(x.month); }}>
            <span style={{ color: "var(--accent)", display: "flex" }}><Icon name={x.icon} size={14} /></span>
            {monthLabel(profile.as_of_date, x.month)} · {x.title}
          </button>
        ))}
      </div>
      <p className="caption" style={{ marginTop: 12, fontSize: 11 }}>
        Your plan in green, current habits in blue · monthly balances from the plan calculation
      </p>
    </section>
  );
}

function Bar({ value, max, color, thin }: { value: number; max: number; color: string; thin?: boolean }) {
  return (
    <div style={{ height: thin ? 5 : 9, borderRadius: 5, background: "var(--raised)", marginTop: thin ? 4 : 0, overflow: "hidden" }}>
      <div style={{ width: `${(value / max) * 100}%`, height: "100%", background: color, borderRadius: 5, transition: "width .12s linear" }} />
    </div>
  );
}

// ---------- Comparison chart ----------

function Comparison({ display, custom }: { display: Display; custom: Projection | null }) {
  const { profile, evaluation } = display;
  const years = display.yearsToRetirement;
  const startYear = Number(profile.as_of_date.slice(0, 4));
  const customYears = custom ? custom.retirement_age - profile.age : 0;
  const span = Math.max(years, customYears);
  const series = useMemo(() => {
    const list: Series[] = [
      { name: "Current habits", values: yearlyBalances(evaluation.projections.current, years), color: "var(--blue)", dashed: true, width: 2 },
      { name: "Your plan", values: yearlyBalances(evaluation.projections.adaptive, years), color: "var(--accent)", area: true, width: 2.4 },
    ];
    if (custom?.feasible) list.push({ name: "Your scenario", values: yearlyBalances(custom, customYears), color: "#f2c46d", width: 2.2 });
    return list;
  }, [evaluation, custom, years, customYears]);

  return (
    <section className="section">
      <h2 className="h-section">Retirement balance</h2>
      <p className="subtitle">Projected by year, before inflation · illustrative assumptions</p>
      <div className="legend" style={{ margin: "16px 0 40px" }}>
        <span style={{ color: "var(--blue)" }}><i className="dashed" /> Current habits</span>
        <span style={{ color: "var(--accent)", fontWeight: 500 }}><i /> Your plan</span>
        {custom?.feasible && <span style={{ color: "#f2c46d", fontWeight: 500 }}><i /> Your scenario</span>}
      </div>
      <LineChart height={230} series={series} renderTooltip={(i) => (
        <div style={{ display: "grid", gap: 3 }}>
          <span>{startYear + i} · Age {profile.age + i}</span>
          {series.map((s) => s.values[i] !== undefined && (
            <span key={s.name}>{s.name} <b style={{ color: s.color }}>{money(s.values[i])}</b></span>
          ))}
        </div>
      )} />
      <div className="axis">
        <span>{startYear}</span>
        <span>{startYear + Math.round(span / 2)}</span>
        <span><b style={{ color: "var(--text-2)", fontWeight: 500 }}>{startYear + span}</b> · Age {profile.age + span}</span>
      </div>
    </section>
  );
}

// ---------- Scenario controls ----------

const scenarioOf = (d: Draft): Scenario => ({
  retirement_age: d.retirementAge,
  employee_contribution_rate: d.policy === "fixed" ? d.fixedRate / 100 : null,
  extra_monthly_debt_cents: d.extraDebt === "" ? null : Math.round((parseAmount(d.extraDebt) ?? 0) * 100),
  priority_style: d.priorityStyle === "same" ? null : d.priorityStyle,
});

function ScenarioControls({ display, onResult, onEdit }: {
  display: Display;
  onResult: (shown: Shown | null) => void;
  /** The person changed a choice by hand (so an opened saved run no longer applies). */
  onEdit: () => void;
}) {
  const { liveEnabled, evaluateScenario, savedPreset, pendingScenario, setPendingScenario } = useStore();
  const { profile } = display;
  const [draft, setDraft] = useState<Draft>(() => original(display));
  const [compared, setCompared] = useState<Draft | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const requestID = useRef(0);

  const edit = (next: Partial<Draft>) => {
    onEdit();
    const updated = { ...draft, ...next };
    setDraft(updated);
    if (!compared || !sameDraft(updated, compared)) {
      requestID.current += 1;
      setCompared(null);
      setStatus(null);
      setBusy(false);
      onResult(null);
    }
  };

  const apply = (preset: Preset) => {
    const next = original(display);
    if (preset === "retire-plus-two") next.retirementAge = Math.min(profile.retirement_age + 2, 80);
    if (preset === "contribution-plus-one") {
      next.policy = "fixed";
      next.fixedRate = Math.min(Math.round((display.rate * 100 + 1) * 2) / 2, 20);
    }
    edit({ ...next, preset });
  };

  const showSaved = async (d: Draft, fallback: string) => {
    const id = requestID.current;
    const saved = d.preset ? await savedPreset(d.preset) : undefined;
    if (id !== requestID.current) return;
    if (saved && d.preset !== "original") {
      onResult({ evaluation: saved, scenario: scenarioOf(d) });
      setStatus("Saved calculation for this preset.");
    } else {
      setStatus(fallback);
    }
  };

  useEffect(() => {
    if (!pendingScenario) return;
    setPendingScenario(null);
    const rate = pendingScenario.employee_contribution_rate;
    const next: Draft = {
      ...original(display),
      retirementAge: pendingScenario.retirement_age,
      policy: rate === null ? "adaptive" : "fixed",
      fixedRate: rate === null ? display.currentRate * 100 : rate * 100,
      extraDebt: pendingScenario.extra_monthly_debt_cents == null ? "" : String(pendingScenario.extra_monthly_debt_cents / 100),
      priorityStyle: pendingScenario.priority_style ?? "same",
      preset: null,
    };
    setDraft(next);
    void compare(next);
  }, [pendingScenario]); // eslint-disable-line react-hooks/exhaustive-deps

  const compare = async (d: Draft = draft) => {
    setCompared(d);
    onResult(null);
    if (sameDraft(d, original(display))) {
      setStatus("This is the saved plan. The chart already shows it.");
      return;
    }
    if (!liveEnabled) {
      showSaved(d, "Turn on live calculation for a custom scenario. Saved presets still work offline.");
      return;
    }
    const id = ++requestID.current;
    setBusy(true);
    setStatus(null);
    try {
      const scenario = scenarioOf(d);
      const result = await evaluateScenario(scenario);
      if (id !== requestID.current) return;
      onResult({ evaluation: result, scenario });
      setStatus(result.projections.custom?.feasible === false
        ? "This scenario can't be funded as entered. See the outcomes below."
        : "Live calculation for this scenario.");
    } catch (error) {
      if (id !== requestID.current) return;
      showSaved(d, errorMessage(error));
    } finally {
      if (id === requestID.current) setBusy(false);
    }
  };

  const fmt = (v: number) => (Number.isInteger(v) ? `${v}%` : `${v.toFixed(1)}%`);
  // Adaptive at the plan's own retirement age is the plan itself: nothing new to compare.
  const atPlan = sameDraft(draft, original(display));

  return (
    <section className="glass card">
      <h2 className="h-section">Try a scenario</h2>
      <p className="subtitle">Change one thing and compare it with your plan.</p>

      <div className="row" style={{ marginTop: 16 }}>
        <span className="field-title">Retirement age</span>
        <span style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <span className="num" style={{ fontSize: 18, fontWeight: 500 }}>{draft.retirementAge}</span>
          <Stepper label="retirement age"
            canDecrement={draft.retirementAge > profile.age + 1} canIncrement={draft.retirementAge < 80}
            onDecrement={() => edit({ retirementAge: draft.retirementAge - 1, preset: null })}
            onIncrement={() => edit({ retirementAge: draft.retirementAge + 1, preset: null })} />
        </span>
      </div>

      <p className="field-title" style={{ margin: "16px 0 10px" }}>Your contribution</p>
      <div className="segmented">
        {(["adaptive", "fixed"] as const).map((p) => (
          <button key={p} aria-pressed={draft.policy === p} onClick={() => edit({ policy: p, preset: null })}>
            {p === "adaptive" ? "Adaptive" : "Fixed rate"}
          </button>
        ))}
      </div>
      <p className="caption" style={{ marginTop: 8 }}>
        {draft.policy === "adaptive"
          ? <>ARM sets it each month, starting at <span className="strong">{percent(display.rate)}</span>.</>
          : "The same rate every month, within plan limits."}
      </p>
      {draft.policy === "fixed" && (
        <div className="row fade-in" style={{ marginTop: 8 }}>
          <span className="label">Fixed rate</span>
          <span style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <span className="num" style={{ fontSize: 18, fontWeight: 500 }}>{fmt(draft.fixedRate)}</span>
            <Stepper label="fixed rate" canDecrement={draft.fixedRate > 0} canIncrement={draft.fixedRate < 20}
              onDecrement={() => edit({ fixedRate: Math.max(draft.fixedRate - 0.5, 0), preset: null })}
              onIncrement={() => edit({ fixedRate: Math.min(draft.fixedRate + 0.5, 20), preset: null })} />
          </span>
        </div>
      )}

      <div className="row" style={{ marginTop: 16 }}>
        <label className="field" style={{ width: "100%" }}>
          <span className="field-label">Extra monthly debt payment</span>
          <input inputMode="decimal" placeholder="Automatic priority" value={draft.extraDebt}
            onChange={(e) => edit({ extraDebt: e.target.value, preset: null })} />
        </label>
      </div>
      <p className="caption">An entered amount goes to the highest APR debt first, up to the amount owed. ARM won't add more than this budget.</p>
      <label className="field" style={{ marginTop: 16 }}>
        <span className="field-label">Priority style</span>
        <select value={draft.priorityStyle} onChange={(e) => edit({ priorityStyle: e.target.value as Draft["priorityStyle"], preset: null })}>
          <option value="same">Keep plan style</option><option value="balanced">Balanced (user override)</option>
          <option value="cash_security">Cash security (user override)</option><option value="debt_reduction">Debt reduction (user override)</option>
        </select>
      </label>

      <button className="btn-primary full" style={{ marginTop: 20 }} onClick={() => compare()}
        disabled={busy || atPlan || (draft.extraDebt !== "" && parseAmount(draft.extraDebt) === null)}>
        {busy ? <span className="spinner" /> : <Icon name="compare" />} Compare scenario
      </button>
      <p className="caption" style={{ marginTop: 10 }} role="status">
        {atPlan ? "This is your plan as it stands. Change a choice above to compare."
          : compared && status ? status : null}
      </p>

      <p className="field-title" style={{ margin: "20px 0 10px" }}>Quick scenarios</p>
      <div className="quick-row">
        {([["original", "Your plan"], ["retire-plus-two", "Retire 2 years later"], ["contribution-plus-one", "Save 1 pt more"]] as const).map(([id, label]) => (
          <button key={id} className={`pill small ${draft.preset === id ? "selected" : "neutral"}`} onClick={() => apply(id)}>
            {label}
          </button>
        ))}
      </div>
    </section>
  );
}

// ---------- Outcomes ----------

function Outcomes({ evaluation, custom, asOf }: { evaluation: Evaluation; custom: Projection | null; asOf: string }) {
  const columns: [string, Projection][] = [["Current habits", evaluation.projections.current], ["Your plan", evaluation.projections.adaptive]];
  if (custom) columns.push(["Your scenario", custom]);
  const when = (m: number | null) => (m === null ? "Not by retirement" : m === 0 ? "Already" : monthLabel(asOf, m));
  const cash = (v: number | null) => (v === null ? "—" : money(v));
  const rows: [string, (p: Projection) => string][] = [
    ["Retirement-account balance", (p) => cash(p.retirement_balance_nominal_cents)],
    ["In today's dollars", (p) => cash(p.retirement_balance_today_cents)],
    ["Debt-free", (p) => when(p.debt_free_month)],
    ["Total debt interest", (p) => cash(p.cumulative_debt_interest_cents)],
    ["One-month cushion", (p) => when(p.starter_reserve_month)],
    ["Emergency fund full", (p) => when(p.full_reserve_month)],
    ["Cash at retirement", (p) => cash(p.cash_nominal_cents)],
    ["Debt at retirement", (p) => cash(p.debt_nominal_cents)],
  ];
  return (
    <section className="section">
      <h2 className="h-section">The whole picture</h2>
      <p className="subtitle" style={{ marginBottom: 16 }}>Debt, interest and emergency cash alongside the balance.</p>
      <table className="table">
        <thead>
          <tr><th />{columns.map(([name]) => <th key={name} style={{ color: name === "Your plan" ? "var(--accent)" : name === "Current habits" ? "var(--blue)" : "#f2c46d" }}>{name}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map(([title, value]) => (
            <tr key={title}>
              <td>{title}</td>
              {columns.map(([name, p]) => <td key={name} className={p.feasible ? "" : "muted"}>{p.feasible ? value(p) : "Not fundable"}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="caption" style={{ marginTop: 14 }}>Before inflation, from the plan calculation · illustrative assumptions.</p>
    </section>
  );
}
