import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { AllocationRing, Icon, MonthMeter } from "../components/ui";
import { LineChart } from "../components/LineChart";
import { Tabs, type TabItem } from "../components/Tabs";
import { Term } from "../components/Term";
import { yearlyBalances, type Display } from "../data/display";
import { money, moneyExact, monthLabel, months, percent } from "../data/format";
import { STYLE_INFO } from "../data/styles";
import { useStore, type PlanSection } from "../store";
import { StyleComparison } from "./StyleComparison";

/** "Sep 2027", or the given words for "already" (month 0) and "never within the plan" (null). */
export function when(month: number | null, asOf: string, done = "Already", never = "Not before retirement"): string {
  if (month === null) return never;
  return month === 0 ? done : monthLabel(asOf, month);
}

/**
 * Your plan: where you're heading (always visible), then one topic per tab. Every tab opens
 * with a one-sentence summary and has its own "Why this matters". All numbers come from the
 * engine's response; the app only looks values up.
 */
export function Plan({ display }: { display: Display }) {
  const { planSection, setPlanSection, planJump, style } = useStore();
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
    { id: "style", label: "Plan style", hint: STYLE_INFO[style].label },
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
            {section === "style" && <StyleComparison />}
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
  const [year, setYear] = useState(years);
  useEffect(() => setYear(years), [years, profile.id]);

  const plan = useMemo(() => yearlyBalances(adaptive, years), [adaptive, years]);
  const habits = useMemo(() => yearlyBalances(current, years), [current, years]);
  const startYear = Number(profile.as_of_date.slice(0, 4));
  const markers = [
    { month: adaptive.debt_free_month, label: "Debt cleared" },
    { month: adaptive.full_reserve_month, label: "Emergency fund full" },
  ].filter((m): m is { month: number; label: string } => m.month !== null && m.month > 0 && m.month <= years * 12)
    .map((m) => ({ index: Math.ceil(m.month / 12), label: m.label }));
  const atEnd = year === years;

  return (
    <section className="future glass card" aria-labelledby="future-title">
      <div className="future-top">
        <div>
          <h2 id="future-title" className="eyebrow" style={{ padding: 0 }}>Where your plan is heading</h2>
          <p className="future-figure num">{money(adaptive.retirement_balance_nominal_cents ?? plan[plan.length - 1] ?? 0)}</p>
          <p className="body future-sub">
            at age {profile.retirement_age}, in {startYear + years}
            {adaptive.retirement_balance_today_cents !== null && (
              <> · about <b className="strong">{money(adaptive.retirement_balance_today_cents)}</b> in <Term id="todays-dollars">today's dollars</Term></>
            )}
          </p>
        </div>
        <div className="future-compare">
          <span className="caption"><Term id="current-habits">If you keep current habits</Term></span>
          <span className="num">{money(current.retirement_balance_nominal_cents ?? habits[habits.length - 1] ?? 0)}</span>
        </div>
      </div>

      <div className="future-readout" aria-live="polite">
        <span className="label">{atEnd ? "At retirement" : `At age ${profile.age + year}`} · {startYear + year}</span>
        <span><i className="dot-plan" /> Your plan <b className="num">{money(plan[year] ?? 0)}</b></span>
        <span><i className="dot-habits" /> Current habits <b className="num">{money(habits[year] ?? 0)}</b></span>
      </div>

      <LineChart height={210} index={year} onIndex={(i) => i !== null && setYear(i)} markers={markers}
        series={[
          { name: "Current habits", values: habits, color: "var(--blue)", dashed: true, width: 2 },
          { name: "Your plan", values: plan, color: "var(--accent)", area: true, width: 2.6 },
        ]} />

      <label className="age-slider">
        <span className="sr-only">Choose an age to see your projected balance</span>
        <input type="range" min={0} max={years} step={1} value={year} onChange={(e) => setYear(Number(e.target.value))}
          aria-valuetext={`Age ${profile.age + year}`} />
        <span className="age-slider-ends"><span>Today · {profile.age}</span><span>Drag to see any age</span><span>{profile.retirement_age}</span></span>
      </label>

      <p className="caption" style={{ marginTop: 10 }}>
        A <Term id="projection">projection</Term> with steady illustrative returns. Real markets rise and fall.
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
  const { profile } = display;
  const minimums = display.debts.reduce((s, d) => s + d.minimumCents, 0);
  const steps = display.cash.filter((c) => c.amountCents > 0 || c.kind === "retirement");
  const title = { retirement: "Retirement contribution", debt: "Extra toward debt", emergency: "Emergency savings", remaining: "Left for you" } as const;
  const note = {
    retirement: "What saving costs you after tax savings",
    debt: "On top of the minimum payment",
    emergency: "Into your cash cushion",
    remaining: "Yours to spend or save",
  } as const;
  return (
    <div className="panel">
      <PanelHead title="Where this month's money goes" short={display.nextStep.headline} why="month" />
      <p className="panel-note">
        First, the basics: {money(profile.monthly_living_expenses_cents)} for living costs
        {minimums > 0 && <> and {money(minimums)} in minimum debt payments</>}. Then:
      </p>
      <ol className="money-steps">
        {steps.map((c) => (
          <li key={c.kind}>
            <span className="money-step-text"><b>{title[c.kind]}</b><span className="caption">{note[c.kind]}</span></span>
            <span className="num money-step-amount">{moneyExact(c.amountCents)}<span className="caption"> /mo</span></span>
          </li>
        ))}
      </ol>
    </div>
  );
}

function Saving({ display }: { display: Display }) {
  const fullMatch = display.evaluation.financial_state.employee_rate_for_full_match;
  const employer = display.employerCents;
  const short = employer
    ? <>You put in {moneyExact(display.employeeCents)} a month and your employer adds {moneyExact(employer)}.</>
    : <>You put in {moneyExact(display.employeeCents)} a month.</>;
  return (
    <div className="panel">
      <PanelHead title="Saving for retirement" short={short} why="saving" />
      <div className="kstats">
        <Stat label="Your contribution" value={percent(display.rate)} sub={display.rate !== display.currentRate ? `Today: ${percent(display.currentRate)}` : "of your pay"} accent />
        <Stat label={<Term id="employer-match">Employer adds</Term>} value={employer === null ? "—" : moneyExact(employer)}
          sub={fullMatch === null ? "No match" : display.matchCaptured ? "Full match" : `Full match at ${percent(fullMatch)}`} />
        <Stat label="Cost to your take-home" value={moneyExact(display.takeHomeCostCents)} sub="per month, after tax savings" />
      </div>
    </div>
  );
}

function Debt({ display }: { display: Display }) {
  const { evaluation, profile } = display;
  const { adaptive, current } = evaluation.projections;
  const paying = display.debts.find((d) => d.extraCents > 0);
  const short = paying
    ? <>Paying {moneyExact(paying.extraCents)} extra clears high-interest debt by {when(adaptive.debt_free_month, profile.as_of_date, "now")}.</>
    : <>Minimum payments keep your debt on schedule.</>;
  return (
    <div className="panel">
      <PanelHead title="Paying down debt" short={short} why="debt" />
      {display.debts.map((d) => (
        <div key={d.id} className="kstats">
          <Stat label={d.name} value={money(d.balanceCents)} sub={<>{percent(d.apr)} <Term id="apr">APR</Term></>} />
          <Stat label="Monthly payment" value={moneyExact(d.minimumCents + d.extraCents)} sub={d.extraCents > 0 ? `${moneyExact(d.minimumCents)} minimum + ${moneyExact(d.extraCents)} extra` : "Minimum"} accent />
          <Stat label={<Term id="high-interest-debt">High-interest debt cleared</Term>} value={when(adaptive.debt_free_month, profile.as_of_date, "None")}
            sub={`Current habits: ${when(current.debt_free_month, profile.as_of_date, "None")}`} />
        </div>
      ))}
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
    rows.push({ key: "debt", title: "High-interest debt cleared", when: when(adaptive.debt_free_month, profile.as_of_date), done: adaptive.debt_free_month === 0, section: "debt" });
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
  style: "The six ideas behind your plan",
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
