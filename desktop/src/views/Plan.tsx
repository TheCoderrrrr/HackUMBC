import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { AllocationRing, Icon, MonthMeter } from "../components/ui";
import { LineChart } from "../components/LineChart";
import { Tabs, type TabItem } from "../components/Tabs";
import { Term } from "../components/Term";
import { monthBudget, yearlyBalances, type Display } from "../data/display";
import { firstReach, gapAt, goalPresets, moneyShort, parseGoal, yearMarkers, yearsSooner } from "../data/chart";
import { money, moneyExact, monthLabel, months, percent, when } from "../data/format";
import { useStore, type PlanSection } from "../store";


/**
 * Your plan: where you're heading (always visible), then one topic per tab. Every tab opens
 * with a one-sentence summary and has its own "Why this matters". All numbers come from the
 * engine's response; the app only looks values up.
 */
export function Plan({ display }: { display: Display }) {
  const { planSection, setPlanSection, planJump } = useStore();
  const { profile } = display;
  const tabsRef = useRef<HTMLDivElement>(null);
  const hasDebt = display.debts.length > 0;
  const section: PlanSection = !hasDebt && planSection === "debt" ? "month" : planSection;

  useEffect(() => {
    if (planJump) tabsRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [planJump]);

  const paying = display.debts.find((d) => d.extraCents > 0);
  const items: TabItem<PlanSection>[] = [
    { id: "month", label: "This month", hint: display.nextStep.amountCents !== null ? moneyExact(display.nextStep.amountCents) : "On course" },
    { id: "saving", label: "Saving", hint: `${percent(display.rate)} of pay` },
    ...(hasDebt ? [{ id: "debt" as const, label: "Debt", hint: paying ? `${moneyExact(paying.extraCents)} extra` : "Minimums" }] : []),
    { id: "emergency", label: "Emergency fund", hint: months(display.emergencyMonths) },
    { id: "fund", label: "Your fund", hint: `${percent(display.equityWeight)} stocks` },
  ];

  return (
    <div className="plan-page fade-in" key={profile.id}>
      <Future display={display} />
      <div className="plan-body">
        <div ref={tabsRef} className="plan-tabs section">
          <Tabs items={items} value={section} onChange={setPlanSection} label="Plan sections">
            {section === "month" && <ThisMonth display={display} />}
            {section === "saving" && <Saving display={display} />}
            {section === "debt" && <Debt display={display} />}
            {section === "emergency" && <Emergency display={display} />}
            {section === "fund" && <Fund display={display} />}
          </Tabs>
        </div>
        <aside className="plan-aside">
          <Milestones display={display} />
          <LearnHint section={section} />
        </aside>
      </div>
    </div>
  );
}

// ---------- Where you're heading ----------

function Future({ display }: { display: Display }) {
  const { profile, evaluation } = display;
  const { adaptive, current } = evaluation.projections;
  const years = display.yearsToRetirement;
  const [pinned, setPinned] = useState(years);
  const [hover, setHover] = useState<number | null>(null);
  const [goal, setGoalState] = useState<number | null>(() => readGoal(profile.id));
  const setGoal = (value: number | null) => {
    setGoalState(value);
    writeGoal(profile.id, value);
  };
  const [custom, setCustom] = useState("");
  const [customError, setCustomError] = useState(false);
  useEffect(() => {
    setPinned(years);
    setGoalState(readGoal(profile.id));
  }, [years, profile.id]);

  const plan = useMemo(() => yearlyBalances(adaptive, years), [adaptive, years]);
  const habits = useMemo(() => yearlyBalances(current, years), [current, years]);
  const presets = useMemo(() => goalPresets(plan[years] ?? 0), [plan, years]);
  const startYear = Number(profile.as_of_date.slice(0, 4));
  const markers = yearMarkers([
    { month: adaptive.debt_free_month, label: "Debt-free" },
    { month: adaptive.full_reserve_month, label: "Emergency fund full" },
  ], years);

  const shown = hover ?? pinned;
  const gap = gapAt(plan, habits, shown);
  const planReach = goal === null ? null : firstReach(plan, goal);
  const habitsReach = goal === null ? null : firstReach(habits, goal);
  const sooner = goal === null ? null : yearsSooner(plan, habits, goal);

  const applyCustom = () => {
    const cents = parseGoal(custom);
    setCustomError(cents === null);
    if (cents !== null) setGoal(cents);
  };
  const reachText = (i: number | null) => (i === null ? "not before retirement" : `at age ${profile.age + i} (${startYear + i})`);

  return (
    <section className="future glass card" aria-labelledby="future-title">
      <div className="future-top">
        <div>
          <h2 id="future-title" className="eyebrow" style={{ padding: 0 }}>Where your plan is heading</h2>
          <p className="future-figure num">{money(adaptive.retirement_balance_nominal_cents ?? plan[years] ?? 0)}</p>
          <p className="body future-sub">
            at age {profile.retirement_age}, in {startYear + years}
            {adaptive.retirement_balance_today_cents !== null && (
              <> · about <b className="strong">{money(adaptive.retirement_balance_today_cents)}</b> in <Term id="todays-dollars">today's dollars</Term></>
            )}
          </p>
        </div>
        <div className="future-compare">
          <span className="caption"><Term id="current-habits">If you keep current habits</Term></span>
          <span className="num">{money(current.retirement_balance_nominal_cents ?? habits[years] ?? 0)}</span>
        </div>
      </div>

      <div className="future-readout" aria-live="polite">
        <span className="label">
          {hover !== null ? "Previewing" : shown === years ? "At retirement" : "Pinned"} · age {profile.age + shown}, {startYear + shown}
        </span>
        <span><i className="dot-plan" /> Your plan <b className="num">{money(plan[shown] ?? 0)}</b></span>
        <span><i className="dot-habits" /> Current habits <b className="num">{money(habits[shown] ?? 0)}</b></span>
        {gap !== null && (
          <span className={`gap-chip ${gap >= 0 ? "up" : "down"}`}>
            {gap >= 0 ? "+" : "−"}{money(Math.abs(gap))} {gap >= 0 ? "ahead" : "behind"}
          </span>
        )}
      </div>

      <LineChart height={230} index={pinned} onIndex={setHover} onPick={setPinned} markers={markers} formatY={moneyShort}
        band={{ upper: "Your plan", lower: "Current habits", color: "#a8e6a1" }}
        goal={goal === null ? null : { value: goal, label: `Goal ${moneyShort(goal)}` }}
        series={[
          { name: "Current habits", values: habits, color: "var(--blue)", dashed: true, width: 2 },
          { name: "Your plan", values: plan, color: "var(--accent)", width: 2.6 },
        ]} />

      <label className="age-slider">
        <span className="sr-only">Choose an age to see your projected balance</span>
        <input type="range" min={0} max={years} step={1} value={pinned} onChange={(e) => setPinned(Number(e.target.value))}
          aria-valuetext={`Age ${profile.age + pinned}`} />
        <span className="age-slider-ends"><span>Today · {profile.age}</span><span>Click the chart or drag to pin an age</span><span>{profile.retirement_age}</span></span>
      </label>

      <div className="goal-bar">
        <span className="goal-title">Set a goal line</span>
        <div className="goal-options" role="group" aria-label="Goal amount">
          {presets.map((p) => (
            <button key={p} className={`pill ${goal === p ? "selected" : "neutral"}`} aria-pressed={goal === p} onClick={() => setGoal(goal === p ? null : p)}>
              {moneyShort(p)}
            </button>
          ))}
          <form className="goal-custom" onSubmit={(e) => { e.preventDefault(); applyCustom(); }}>
            <input value={custom} onChange={(e) => { setCustom(e.target.value); setCustomError(false); }} placeholder="Your amount, e.g. 1.2m"
              aria-label="Custom goal amount" aria-invalid={customError} />
            <button className="pill neutral" type="submit">Set</button>
          </form>
          {goal !== null && <button className="link" onClick={() => setGoal(null)}>Clear</button>}
        </div>
        {customError && <p className="caption goal-error">Enter an amount like 800k, 1.2m or 1,000,000.</p>}
        {goal !== null && (
          <p className="goal-result">
            Your plan reaches {moneyShort(goal)} <b>{reachText(planReach)}</b>; current habits {reachText(habitsReach)}.
            {sooner !== null && sooner > 0 && <> That's <b>{sooner} {sooner === 1 ? "year" : "years"} sooner</b>.</>}
          </p>
        )}
      </div>

      <p className="caption" style={{ marginTop: 12 }}>
        The shaded area is the difference between your plan and current habits. A <Term id="projection">projection</Term> with
        steady illustrative returns; real markets rise and fall.
      </p>
    </section>
  );
}

// ---------- Section panels ----------

function PanelHead({ title, short, why }: { title: string; short: ReactNode; why: PlanSection }) {
  const { setDrawer } = useStore();
  return (
    <div className="panel-head">
      <div>
        <h3 className="h-section">{title}</h3>
        <p className="panel-short">{short}</p>
      </div>
      <button className="pill neutral why-btn" onClick={() => setDrawer({ why })}>
        <Icon name="why" /> Why this matters
      </button>
    </div>
  );
}

function Stat({ label, value, sub, accent }: { label: ReactNode; value: string; sub?: ReactNode; accent?: boolean }) {
  return (
    <div className="kstat">
      <span className="kstat-label">{label}</span>
      <span className={`kstat-value num ${accent ? "accent" : ""}`}>{value}</span>
      {sub && <span className="kstat-sub">{sub}</span>}
    </div>
  );
}

function ThisMonth({ display }: { display: Display }) {
  const b = monthBudget(display);
  const balanced = b.totalCents === b.toPlanCents;
  const blocked = display.evaluation.financial_state.warnings.includes("CASH_FLOW_SHORTFALL");
  return (
    <div className="panel">
      <PanelHead title="Where this month's money goes" short={display.nextStep.headline} why="month" />
      <div className="budget">
        <div className="budget-line">
          <span>Take-home pay</span><span className="num">{moneyExact(b.takeHomeCents)}</span>
        </div>
        {b.currentContributionCents > 0 && (
          <div className="budget-line">
            <span>
              + Your current 401(k) contribution
              <span className="caption"> · already taken out of your pay, so it's part of what ARM can direct</span>
            </span>
            <span className="num">{moneyExact(b.currentContributionCents)}</span>
          </div>
        )}
        <div className="budget-line budget-sum">
          <span>Money to plan with</span><span className="num">{moneyExact(b.toPlanCents)}</span>
        </div>
      </div>
      <ol className="money-steps">
        {b.lines.map((l) => (
          <li key={l.key}>
            <span className="money-step-text"><b>{l.label}</b><span className="caption">{l.note}</span></span>
            <span className="num money-step-amount">{moneyExact(l.cents)}<span className="caption"> /mo</span></span>
          </li>
        ))}
      </ol>
      <p className={`budget-check ${balanced ? "ok" : "off"}`}>
        {balanced
          ? <><Icon name="check" size={13} /> Adds up to {moneyExact(b.totalCents)}, every dollar accounted for.</>
          : blocked
            ? "Living costs and minimum payments are more than the money available, so nothing else can be funded yet."
            : `These lines total ${moneyExact(b.totalCents)}; the engine's budget is ${moneyExact(b.toPlanCents)}.`}
      </p>
    </div>
  );
}

function Saving({ display }: { display: Display }) {
  const state = display.evaluation.financial_state;
  const fullMatch = state.employee_rate_for_full_match;
  const employer = display.employerCents;
  const short = employer
    ? <>You put in {moneyExact(display.employeeCents)} a month and your employer adds {moneyExact(employer)}.</>
    : <>You put in {moneyExact(display.employeeCents)} a month.</>;
  const changed = Math.abs(display.rate - display.currentRate) > 1e-9;
  return (
    <div className="panel">
      <PanelHead title="Saving for retirement" short={short} why="saving" />
      <div className="kstats">
        <Stat label="Your contribution" value={percent(display.rate)} accent
          sub={changed ? `${display.rate > display.currentRate ? "Up" : "Down"} from ${percent(display.currentRate)} today` : "of your pay"} />
        <Stat label={<Term id="employer-match">Employer adds</Term>} value={employer === null ? "—" : moneyExact(employer)}
          sub={fullMatch === null ? "No match" : display.matchCaptured ? "Full match, per month" : `Full match needs ${percent(fullMatch)}`} />
        <Stat label="Cost to your take-home" value={moneyExact(display.takeHomeCostCents)}
          sub={display.profile.contribution_tax_treatment === "roth"
            ? "Roth: taxed now, so the full amount comes from take-home"
            : `${moneyExact(display.employeeCents)} goes in; lower income tax covers the rest`} />
      </div>
      {changed && display.rate < display.currentRate && (
        <p className="panel-note">
          The plan lowers your contribution for now to free cash for {display.debts.some((d) => d.extraCents > 0) ? "expensive debt" : "your emergency fund"},
          while still keeping {display.matchCaptured ? "the full employer match" : "as much of the match as it can"}. It rises again once that's handled.
        </p>
      )}
    </div>
  );
}

function Debt({ display }: { display: Display }) {
  const { evaluation, profile } = display;
  const { adaptive, current } = evaluation.projections;
  const threshold = evaluation.assumptions.high_interest_apr_threshold;
  const paying = display.debts.find((d) => d.extraCents > 0);
  const short = paying
    ? <>Paying {moneyExact(paying.extraCents)} extra on your {paying.name.toLowerCase()} makes you debt-free by {when(adaptive.debt_free_month, profile.as_of_date, "now")}.</>
    : <>Minimum payments keep every debt on schedule; no extra payments are needed.</>;
  return (
    <div className="panel">
      <PanelHead title="Paying down debt" short={short} why="debt" />
      <table className="table debt-table">
        <thead><tr><th>Debt</th><th>Balance</th><th><Term id="apr">APR</Term></th><th>Minimum</th><th>Extra this month</th></tr></thead>
        <tbody>
          {display.debts.map((d) => (
            <tr key={d.id}>
              <td>{d.name}{d.apr >= threshold && <span className="chip muted" style={{ marginLeft: 8 }}><Term id="high-interest-debt">High interest</Term></span>}</td>
              <td className="num">{money(d.balanceCents)}</td>
              <td className="num">{percent(d.apr)}</td>
              <td className="num">{moneyExact(d.minimumCents)}</td>
              <td className="num" style={{ color: d.extraCents > 0 ? "var(--accent)" : undefined }}>{d.extraCents > 0 ? moneyExact(d.extraCents) : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="kstats">
        <Stat label="Debt-free (every debt paid off)" value={when(adaptive.debt_free_month, profile.as_of_date, "Now")} accent
          sub={`Current habits: ${when(current.debt_free_month, profile.as_of_date, "now")}`} />
        <Stat label="Interest you'll pay" value={money(adaptive.cumulative_debt_interest_cents ?? 0)}
          sub={`Current habits: ${money(current.cumulative_debt_interest_cents ?? 0)}`} />
        <Stat label="Paid each month now" value={moneyExact(display.debts.reduce((s, d) => s + d.minimumCents + d.extraCents, 0))}
          sub="Minimums plus any extra" />
      </div>
    </div>
  );
}

function Emergency({ display }: { display: Display }) {
  const { evaluation, profile } = display;
  const { adaptive } = evaluation.projections;
  const funded = display.emergencyMonths >= display.fullMonths;
  const short = funded
    ? <>You have {months(display.emergencyMonths)} of living costs saved, above the {display.fullMonths}-month target.</>
    : <>You have {months(display.emergencyMonths)} saved. The plan reaches {display.fullMonths} months by {when(adaptive.full_reserve_month, profile.as_of_date)}.</>;
  return (
    <div className="panel">
      <PanelHead title="Your emergency fund" short={short} why="emergency" />
      <div className="kstats">
        <Stat label="Saved now" value={money(profile.emergency_cash_cents)} sub={months(display.emergencyMonths)} accent />
        <Stat label={<Term id="cushion">One-month cushion</Term>} value={money(display.starterTargetCents)} sub={display.emergencyMonths >= display.starterMonths ? "Reached" : "Building"} />
        <Stat label={<Term id="emergency-fund">Full target</Term>} value={money(display.fullTargetCents)} sub={funded ? "Reached" : `By ${when(adaptive.full_reserve_month, profile.as_of_date)}`} />
      </div>
      <div style={{ marginTop: 18 }}><MonthMeter months={display.emergencyMonths} target={display.fullMonths} /></div>
    </div>
  );
}

function Fund({ display }: { display: Display }) {
  const short = <>Your fund stays as it is: about {percent(display.equityWeight)} stocks now, shifting toward bonds as you near retirement.</>;
  return (
    <div className="panel">
      <PanelHead title="Your target-date fund" short={short} why="fund" />
      <div className="fund-row">
        <AllocationRing stocks={display.equityWeight} />
        <div className="kstats" style={{ marginTop: 0, flex: 1 }}>
          <Stat label="Stocks" value={percent(display.equityWeight)} sub="for growth" accent />
          <Stat label="Bonds" value={percent(1 - display.equityWeight)} sub="for stability" />
          <Stat label={<Term id="glide-path">Glide path</Term>} value="Automatic" sub="Shifts to bonds over time" />
        </div>
      </div>
    </div>
  );
}

// ---------- Side rail ----------

/** The plan's key dates, in order, from the engine's projection. */
function Milestones({ display }: { display: Display }) {
  const { openPlan } = useStore();
  const { profile, evaluation } = display;
  const { adaptive } = evaluation.projections;
  const rows: { key: string; title: string; when: string; done: boolean; section?: PlanSection; value?: string }[] = [
    { key: "today", title: "Today", when: monthLabel(profile.as_of_date, 0), done: true, value: `${money(profile.retirement_balance_cents)} saved` },
  ];
  if (display.debts.length > 0 && adaptive.debt_free_month !== null) {
    rows.push({ key: "debt", title: "Debt-free", when: when(adaptive.debt_free_month, profile.as_of_date), done: adaptive.debt_free_month === 0, section: "debt" });
  }
  if (adaptive.full_reserve_month !== null) {
    rows.push({ key: "fund", title: "Emergency fund full", when: when(adaptive.full_reserve_month, profile.as_of_date), done: adaptive.full_reserve_month === 0, section: "emergency" });
  }
  rows.push({
    key: "retire", title: `Retire at ${profile.retirement_age}`, when: `${Number(profile.as_of_date.slice(0, 4)) + display.yearsToRetirement}`,
    done: false, value: adaptive.retirement_balance_nominal_cents === null ? undefined : money(adaptive.retirement_balance_nominal_cents),
  });
  return (
    <section className="section milestones" aria-labelledby="milestones-title">
      <h3 id="milestones-title" className="h-card">Milestones</h3>
      <ol>
        {rows.map((r) => (
          <li key={r.key} className={r.done ? "done" : ""}>
            <span className="ms-dot" aria-hidden="true">{r.done && <Icon name="check" size={10} />}</span>
            <span className="ms-text">
              {r.section ? <button className="ms-title link-quiet" onClick={() => openPlan(r.section!)}>{r.title}</button>
                : <span className="ms-title">{r.title}</span>}
              <span className="caption">{r.when}{r.value && <> · <b className="num">{r.value}</b></>}</span>
            </span>
          </li>
        ))}
      </ol>
    </section>
  );
}

const LESSON_FOR: Record<PlanSection, string> = {
  month: "The six ideas behind your plan",
  saving: "Get the full employer match",
  debt: "Clear expensive debt early",
  emergency: "Keep an emergency fund",
  fund: "Know what your fund does",
};

/** A pointer to the Learn lesson behind the open section. */
function LearnHint({ section }: { section: PlanSection }) {
  const { setTab } = useStore();
  return (
    <button className="learn-hint" onClick={() => setTab("learn")}>
      <span className="guide-icon"><Icon name="learn" /></span>
      <span>
        <span className="caption" style={{ display: "block" }}>New to this?</span>
        <span className="strong" style={{ fontSize: 14 }}>{LESSON_FOR[section]}</span>
      </span>
      <Icon name="chevron" size={14} />
    </button>
  );
}

// The goal line is a per-viewer convenience, so it lives in this browser only.
function readGoal(profileID: string): number | null {
  try {
    const n = Number(localStorage.getItem(`goal:${profileID}`));
    return Number.isFinite(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

function writeGoal(profileID: string, cents: number | null) {
  try {
    if (cents === null) localStorage.removeItem(`goal:${profileID}`);
    else localStorage.setItem(`goal:${profileID}`, String(cents));
  } catch {
    // Storage can be unavailable (private mode); the goal just won't be remembered.
  }
}

