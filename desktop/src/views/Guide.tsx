import { useEffect, useRef, useState, type ReactNode } from "react";
import { Icon } from "../components/ui";
import { Term } from "../components/Term";
import { monthBudget, monthStepCents, type Display } from "../data/display";
import { money, moneyExact, months, percent } from "../data/format";
import { PRIORITY_LABEL, STYLE_INFO } from "../data/styles";
import { useStore, type Tab } from "../store";

const STEPS = 3;

/**
 * Getting started (a modal dialog, shown once per browser and anytime from the sidebar). Three
 * pages, all built from the selected person's live result: a welcome with their snapshot, this
 * month's money step by step (interactive), and a tour of every menu item that lights it up in
 * the real sidebar. Every page can be skipped. The plan style itself is set from Plan style.
 */
export function Guide() {
  const { guideOpen, closeGuide, profile, display, setTab } = useStore();
  const [step, setStep] = useState(0);
  const dialog = useRef<HTMLDivElement>(null);
  const returnFocus = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!guideOpen) return;
    setStep(0);
    returnFocus.current = document.activeElement as HTMLElement | null;
    return () => returnFocus.current?.focus?.();
  }, [guideOpen]);

  // Move focus to the step's heading so screen readers announce it.
  useEffect(() => {
    if (guideOpen) dialog.current?.querySelector<HTMLElement>("h2")?.focus();
  }, [guideOpen, step]);

  const leave = (tab?: Tab) => {
    if (tab) setTab(tab);
    closeGuide();
  };

  // Esc leaves; Tab stays inside the dialog.
  useEffect(() => {
    if (!guideOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") leave();
      if (e.key !== "Tab" || !dialog.current) return;
      const items = [...dialog.current.querySelectorAll<HTMLElement>("button:not([disabled]), [href], [tabindex='0']")];
      if (!items.length) return;
      const first = items[0], last = items[items.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  if (!guideOpen) return null;

  const first = profile.name.split(" ")[0];
  const next = () => setStep((s) => Math.min(s + 1, STEPS - 1));
  const back = () => setStep((s) => Math.max(s - 1, 0));

  const pages: { key: string; eyebrow: string; title: string; body: ReactNode; primary: ReactNode }[] = [
    {
      key: "welcome", eyebrow: `Welcome, ${first}`, title: "A retirement plan built from your real finances",
      body: <WelcomePage display={display} name={first} onLearn={() => leave("learn")} />,
      primary: <button className="btn-primary" onClick={next}>See this month's money <Icon name="arrow" /></button>,
    },
    {
      key: "month", eyebrow: "How ARM decides", title: `Where ${first}'s money goes this month`,
      body: display ? <MonthPage display={display} /> : <NoResult />,
      primary: <button className="btn-primary" onClick={next}>Tour the menu <Icon name="arrow" /></button>,
    },
    {
      key: "menu", eyebrow: "Find your way", title: "What each part of the menu does",
      body: <MenuPage onGo={closeGuide} />,
      primary: <button className="btn-primary" onClick={() => leave("plan")}>Open my plan <Icon name="arrow" /></button>,
    },
  ];
  const page = pages[step];

  return (
    <>
      <div className="scrim" />
      <div ref={dialog} className={`guide fade-in ${page.key === "menu" ? "touring" : ""}`} role="dialog" aria-modal="true" aria-labelledby="guide-title">
        <div className="guide-progress" role="progressbar" aria-valuemin={1} aria-valuemax={STEPS} aria-valuenow={step + 1}
          aria-label={`Step ${step + 1} of ${STEPS}`} style={{ gridTemplateColumns: `repeat(${STEPS}, 1fr)` }}>
          {pages.map((p, i) => (
            <button key={p.key} className={i <= step ? "on" : ""} onClick={() => setStep(i)} aria-label={`Go to step ${i + 1}: ${p.eyebrow}`} />
          ))}
        </div>
        <div className="guide-body" key={page.key}>
          <p className="eyebrow" style={{ padding: 0 }}>{page.eyebrow} · {step + 1} of {STEPS}</p>
          <h2 id="guide-title" className="guide-title" tabIndex={-1}>{page.title}</h2>
          {page.body}
          <div className="guide-foot">
            {step > 0 && <button className="pill neutral" onClick={back}>Back</button>}
            <span className="guide-foot-end">
              <button className="link-quiet" onClick={() => leave()}>Skip for now</button>
              {page.primary}
            </span>
          </div>
        </div>
      </div>
    </>
  );
}

function NoResult() {
  return <p className="body guide-lead">Your plan is still loading. Turn on live calculation or pick a demo profile to see your numbers here.</p>;
}

// ---------- 1. Welcome ----------

function WelcomePage({ display, name, onLearn }: { display: Display | null; name: string; onLearn: () => void }) {
  const debt = display?.debts.reduce((s, d) => s + d.balanceCents, 0) ?? 0;
  return (
    <>
      <p className="body guide-lead">
        A <Term id="target-date-fund">target-date fund</Term> plans from your birth year alone. ARM keeps your fund as it is and works
        out, from {name}'s own numbers, how much to save each month and where every extra dollar should go.
      </p>
      {display && (
        <>
          <div className="guide-facts">
            <Fact label="Take-home pay" value={`${money(display.profile.monthly_take_home_cents)}/mo`} />
            <Fact label="Debt" value={debt ? money(debt) : "None"} sub={debt ? `Highest ${percent(Math.max(...display.debts.map((d) => d.apr)))} APR` : undefined} />
            <Fact label="Emergency fund" value={months(display.emergencyMonths)} sub={`Target ${display.fullMonths} months`} />
            <Fact label="Saving now" value={percent(display.currentRate)} sub="of pay" />
          </div>
          <div className="guide-next">
            <span className="guide-icon"><Icon name="flag" /></span>
            <span><span className="caption">ARM's next step for {name}</span><b>{display.nextStep.headline}</b></span>
          </div>
        </>
      )}
      <ol className="guide-map">
        <li><b>This month's money</b><span className="caption">Step through where each dollar goes, with real amounts.</span></li>
        <li><b>Your menu</b><span className="caption">What each page does and what to try first.</span></li>
      </ol>
      <button className="guide-learn" onClick={onLearn}>
        <span className="guide-icon"><Icon name="learn" /></span>
        <span>
          <span className="strong" style={{ display: "block", fontSize: 15 }}>Prefer to read first? Open Learn</span>
          <span className="caption" style={{ fontSize: 13 }}>Six short lessons. Reopen this guide anytime from Getting started.</span>
        </span>
        <Icon name="chevron" />
      </button>
    </>
  );
}

function Fact({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="guide-fact">
      <span className="caption">{label}</span>
      <b className="num">{value}</b>
      {sub && <span className="caption">{sub}</span>}
    </div>
  );
}

// ---------- 2. This month's money, step by step ----------

interface MonthStep {
  key: string;
  title: ReactNode;
  label: string;
  color: string;
  why: ReactNode;
}

const PLAY_MS = 1400;

/** The engine's waterfall with this person's real amounts; click a step or play it through in order. */
function MonthPage({ display }: { display: Display }) {
  const { style, openStyle } = useStore();
  const budget = monthBudget(display);
  const order = display.evaluation.decision_summary.ordered_priorities;
  const target = display.evaluation.assumptions.retirement_total_saving_target;
  const fullMatch = display.evaluation.financial_state.employee_rate_for_full_match;
  const [active, setActive] = useState(0);
  const [playing, setPlaying] = useState(false);

  const steps: MonthStep[] = [
    { key: "essentials", title: "Essentials and minimum payments", label: "Essentials and minimum payments", color: "var(--band-minimum)",
      why: <>Rent, food, bills and every debt's minimum come first, always. Nothing optional is planned until these are covered.</> },
    { key: "retirement", title: <><Term id="employer-match">Employer match</Term> and retirement saving</>, label: "Employer match and retirement saving", color: "var(--band-retirement)",
      why: fullMatch !== null
        ? <>Enough to keep the full match{display.employerCents ? <> (your employer adds <b>{moneyExact(display.employerCents)}</b> a month on top)</> : null},
          then more toward a combined {percent(target)} of pay once the next step's goals are handled.</>
        : <>No employer match here, so this is your own contribution, rising toward a combined {percent(target)} of pay once the next step's goals are handled.</> },
    { key: "style", title: <>Your <Term id="plan-style">plan style</Term>'s goals</>, label: "Your plan style's goals", color: "var(--band-debt)",
      why: <>{STYLE_INFO[style].label} puts these in this order right now: <b>{order.map((p) => PRIORITY_LABEL[p]).join(" → ")}</b>. It's the one
        step you choose. (If cash is below a small safety reserve, topping that up comes before the match; it's counted here.)</> },
    { key: "left", title: "Anything left is yours", label: "Anything left", color: "var(--band-remaining)",
      why: <>Spend it, save it, or put it toward other goals.</> },
  ];
  const cents = monthStepCents(budget.lines);
  const amount = (s: MonthStep) => cents[steps.indexOf(s)];

  useEffect(() => {
    if (!playing) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setActive(steps.length - 1);
      setPlaying(false);
      return;
    }
    const timer = window.setInterval(() => setActive((a) => {
      if (a >= steps.length - 1) { setPlaying(false); return a; }
      return a + 1;
    }), PLAY_MS);
    return () => window.clearInterval(timer);
  }, [playing]); // eslint-disable-line react-hooks/exhaustive-deps

  const play = () => { setActive(0); setPlaying(true); };
  const current = steps[active];
  const funded = steps.slice(0, active + 1).reduce((s, st) => s + amount(st), 0);

  return (
    <>
      <p className="body guide-lead">
        <b className="strong">{moneyExact(budget.toPlanCents)}</b> to plan with each month: take-home pay
        {budget.currentContributionCents > 0 && <> plus the {moneyExact(budget.currentContributionCents)} already going to your 401(k)</>}.
        ARM funds it in this order. Click a step, or play the month.
      </p>

      <div className="month-bar" role="img" aria-label={steps.map((s) => `${s.label} ${moneyExact(amount(s))}`).join(", ")}>
        {steps.map((s, i) => amount(s) > 0 && (
          <span key={s.key} className={`month-seg ${i <= active ? "filled" : ""} ${i === active ? "current" : ""}`}
            style={{ flexGrow: amount(s), background: s.color }} />
        ))}
      </div>
      <div className="month-meter">
        <span className="caption">Funded so far</span>
        <b className="num">{moneyExact(funded)}</b>
        <span className="caption">of {moneyExact(budget.toPlanCents)}</span>
        <button className="pill small neutral" onClick={play} disabled={playing} style={{ marginLeft: "auto" }}>
          <Icon name={playing ? "pause" : "play"} size={13} /> {playing ? "Playing…" : "Play the month"}
        </button>
      </div>

      <div className="month-walk">
        <ol className="month-steps">
          {steps.map((s, i) => (
            <li key={s.key}>
              <button className={i === active ? "on" : i < active ? "done" : ""} aria-current={i === active ? "step" : undefined}
                onClick={() => { setPlaying(false); setActive(i); }}>
                <span className="month-num">{i + 1}</span>
                <span className="month-title">{s.title}</span>
                <span className="num month-amt">{moneyExact(amount(s))}</span>
              </button>
            </li>
          ))}
        </ol>
        <div className="month-why fade-in" key={current.key} aria-live="polite">
          <p className="eyebrow" style={{ padding: 0 }}>Step {active + 1}</p>
          <p className="h-card" style={{ marginTop: 4 }}>{current.title}</p>
          <p className="month-why-amt num">{moneyExact(amount(current))}<span className="caption"> this month</span></p>
          <p className="body small">{current.why}</p>
          {current.key === "style" && (
            <button className="link" style={{ marginTop: 10 }} onClick={openStyle}>Compare plan styles</button>
          )}
        </div>
      </div>
      {budget.totalCents !== budget.toPlanCents && (
        <p className="caption" style={{ marginTop: 10 }}>
          Essentials and minimums are more than the money available, so the other steps can't be funded yet.
        </p>
      )}
    </>
  );
}

// ---------- 3. The menu ----------

interface Feature {
  id: string;
  icon: string;
  title: string;
  does: string;
  tryFirst: string;
  go?: { label: string; run: () => void };
}

/** Every menu item: what it does, what to try, and a way there. The chosen item lights up in the real sidebar. */
function MenuPage({ onGo }: { onGo: () => void }) {
  const { setTab, openStyle, openNumbers } = useStore();
  const to = (tab: Tab) => () => { setTab(tab); onGo(); };
  const features: Feature[] = [
    { id: "overview", icon: "overview", title: "Overview", does: "Where you stand today and the single most useful next step.",
      tryFirst: "Read your next step, then open a tile to see the details.", go: { label: "Open Overview", run: to("overview") } },
    { id: "plan", icon: "plan", title: "Your plan", does: "Your projected balance against current habits, then one topic per tab: this month, saving, debt, emergency fund, your fund.",
      tryFirst: "Drag across the chart and set a goal line to see when you'd reach it.", go: { label: "Open Your plan", run: to("plan") } },
    { id: "style", icon: "sliders", title: "Plan style", does: "Chooses what your extra money pays for first: a cushion, expensive debt or a full emergency fund.",
      tryFirst: "Compare the three styles on one chart and switch anytime.", go: { label: "Open Plan style", run: () => { openStyle(); onGo(); } } },
    { id: "explore", icon: "explore", title: "Explore", does: "What-if scenarios: another retirement age or a fixed contribution, compared with your plan.",
      tryFirst: "Pick \"Retire 2 years later\" and press Compare scenario.", go: { label: "Open Explore", run: to("explore") } },
    { id: "saved", icon: "replay", title: "Saved runs", does: "Plans saved to Tiger Data. Click one to reopen it with the same choices, or compare two over 5, 10 and 20 years.",
      tryFirst: "In Explore, save a scenario, then open the Saved runs tab.", go: { label: "Open Explore", run: to("explore") } },
    { id: "funds", icon: "funds", title: "Fund shortlist", does: "Target-date funds ranked by fit, cost and verified data, side by side with their sources.",
      tryFirst: "Set your risk tolerance and read the side-by-side table.", go: { label: "Open Fund shortlist", run: to("funds") } },
    { id: "people", icon: "person", title: "Your people", does: "Add up to 10 people with their own numbers. Stored privately under an anonymous key.",
      tryFirst: "Add a person, or start from Morgan's numbers to see the form.", go: { label: "Add a person", run: () => { openNumbers(null); onGo(); } } },
    { id: "learn", icon: "learn", title: "Learn", does: "Six short lessons on the ideas behind the plan, each applied to your numbers.",
      tryFirst: "Press Try on a lesson to apply it.", go: { label: "Open Learn", run: to("learn") } },
    { id: "ask", icon: "chat", title: "Ask", does: "Plain-language answers to retirement questions, from Gemini, with sources.",
      tryFirst: "Ask \"What is a target-date fund?\" with the button at the bottom right." },
    { id: "live", icon: "refresh", title: "Live calculation", does: "On: plans are calculated by the server as you change things. Off: saved results, clearly labelled.",
      tryFirst: "Leave it on; the switch is at the bottom of the menu." },
  ];
  const [picked, setPicked] = useState(features[0].id);
  const f = features.find((x) => x.id === picked) ?? features[0];

  // Light up the same item in the real menu (and keep it in view).
  useEffect(() => {
    document.body.dataset.tour = f.id;
    const targets = [...document.querySelectorAll<HTMLElement>(`[data-tour~="${f.id}"]`)];
    targets.forEach((el) => el.classList.add("tour-on"));
    targets[0]?.scrollIntoView?.({ block: "nearest" });
    return () => {
      targets.forEach((el) => el.classList.remove("tour-on"));
      delete document.body.dataset.tour;
    };
  }, [f.id]);

  return (
    <>
      <p className="body guide-lead">Pick an item to see what it's for. It lights up in your menu on the left.</p>
      <div className="menu-tour">
        <div className="menu-list" role="listbox" aria-label="Menu items">
          {features.map((x) => (
            <button key={x.id} role="option" aria-selected={x.id === picked} onClick={() => setPicked(x.id)}>
              <Icon name={x.icon} size={16} /> {x.title}
            </button>
          ))}
        </div>
        <div className="menu-detail fade-in" key={f.id}>
          <span className="guide-icon"><Icon name={f.icon} /></span>
          <p className="h-card" style={{ marginTop: 12 }}>{f.title}</p>
          <p className="body small" style={{ marginTop: 6 }}>{f.does}</p>
          <p className="menu-try"><b>Try first</b> {f.tryFirst}</p>
          {f.go && <button className="pill small" style={{ marginTop: 14 }} onClick={f.go.run}>{f.go.label} <Icon name="arrow" size={13} /></button>}
        </div>
      </div>
    </>
  );
}
