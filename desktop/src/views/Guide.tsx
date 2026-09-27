import { useEffect, useRef, useState, type ReactNode } from "react";
import { Icon } from "../components/ui";
import { budgetSlices, monthBudget, type Display } from "../data/display";
import { money, moneyExact, months, percent } from "../data/format";
import { useStore, type Tab } from "../store";

const STEPS = 3;

/**
 * Getting started (a modal dialog, shown once per browser and anytime from the sidebar). Three
 * pages, all built from the selected person's live result: a welcome with their snapshot, a pie of
 * this month's money (click a slice or line to highlight it), and a tour of every menu item that
 * lights it up in the real sidebar. Every page can be skipped. The plan style is set from Plan style.
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
        ARM keeps your retirement fund as it is and works out, from {name}'s own numbers, how much to save and where each
        extra dollar should go.
      </p>
      {display && (
        <>
          <div className="guide-facts">
            <Fact label="Take-home pay" value={`${money(display.profile.monthly_take_home_cents)}/mo`} />
            <Fact label="Debt" value={debt ? money(debt) : "None"} />
            <Fact label="Emergency fund" value={months(display.emergencyMonths)} />
            <Fact label="Saving now" value={`${percent(display.currentRate)} of pay`} />
          </div>
          <div className="guide-next">
            <span className="guide-icon"><Icon name="flag" /></span>
            <span><span className="caption">ARM's next step for {name}</span><b>{display.nextStep.headline}</b></span>
          </div>
        </>
      )}
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

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div className="guide-fact">
      <span className="caption">{label}</span>
      <b className="num">{value}</b>
    </div>
  );
}

// ---------- 2. This month's money as a pie ----------

const SLICE_COLOR: Record<string, string> = {
  living: "#9aa0b5",
  minimums: "#7f8fbf",
  retirement: "#7fd18a",
  debt: "#6ea8ff",
  emergency: "#5ccdb8",
  remaining: "#e0c27a",
};

const SIZE = 260;
const C = SIZE / 2;
const OUTER = 104;
const INNER = 62;
const POP = 12; // how far a chosen slice grows outward

/** An annular slice from `start` to `end` (fractions of a turn, clockwise from 12 o'clock). */
function slicePath(start: number, end: number, outer: number, inner: number): string {
  // A full circle can't be one arc; split it in two.
  if (end - start >= 0.9999) return slicePath(0, 0.5, outer, inner) + slicePath(0.5, 1, outer, inner);
  const point = (turn: number, r: number) => {
    const a = turn * 2 * Math.PI - Math.PI / 2;
    return `${(C + r * Math.cos(a)).toFixed(3)} ${(C + r * Math.sin(a)).toFixed(3)}`;
  };
  const large = end - start > 0.5 ? 1 : 0;
  return `M ${point(start, outer)} A ${outer} ${outer} 0 ${large} 1 ${point(end, outer)} `
    + `L ${point(end, inner)} A ${inner} ${inner} 0 ${large} 0 ${point(start, inner)} Z`;
}

/** Where this month's money goes, as a pie. Clicking a slice or a line makes that slice glow and grow. */
function MonthPage({ display }: { display: Display }) {
  const { openStyle } = useStore();
  const budget = monthBudget(display);
  const slices = budgetSlices(budget.lines);
  const [picked, setPicked] = useState<string | null>(null);
  const chosen = slices.find((s) => s.key === picked) ?? null;
  const toggle = (key: string) => setPicked((p) => (p === key ? null : key));
  const pct = (share: number) => `${(Math.round(share * 1000) / 10).toFixed(1)}%`;

  return (
    <>
      <p className="body guide-lead">
        <b className="strong">{moneyExact(budget.toPlanCents)}</b> to plan with each month: take-home pay
        {budget.currentContributionCents > 0 && <> plus what already goes to the 401(k)</>}. Click a slice or a line to see it.
      </p>

      <div className="pie-page">
        <div className="pie" style={{ width: SIZE, height: SIZE }}>
          <svg viewBox={`0 0 ${SIZE} ${SIZE}`} width={SIZE} height={SIZE} role="img"
            aria-label={slices.map((s) => `${s.label} ${pct(s.share)}`).join(", ")}>
            {slices.map((s) => {
              const on = s.key === picked;
              return (
                <path key={s.key} d={slicePath(s.start, s.end, on ? OUTER + POP : OUTER, INNER)} fill={SLICE_COLOR[s.key] ?? "#888"}
                  className={`pie-slice ${on ? "on" : picked ? "dim" : ""}`}
                  style={{ ["--glow" as string]: SLICE_COLOR[s.key] ?? "#888" }}
                  onClick={() => toggle(s.key)} />
              );
            })}
          </svg>
          <div className="pie-center" aria-live="polite">
            {chosen ? (
              <><b className="num">{pct(chosen.share)}</b><span className="num">{moneyExact(chosen.cents)}</span><span>{chosen.label}</span></>
            ) : (
              <><b className="num">{moneyExact(budget.totalCents)}</b><span>this month</span></>
            )}
          </div>
        </div>

        <ul className="pie-legend">
          {slices.map((s) => (
            <li key={s.key}>
              <button className={s.key === picked ? "on" : ""} aria-pressed={s.key === picked} onClick={() => toggle(s.key)}
                style={{ ["--glow" as string]: SLICE_COLOR[s.key] ?? "#888" }}>
                <i style={{ background: SLICE_COLOR[s.key] }} />
                <span className="pie-legend-text"><b>{s.label}</b>{s.key === picked && <span className="caption">{s.note}</span>}</span>
                <span className="num pie-legend-amt">{moneyExact(s.cents)}</span>
                <span className="num pie-legend-pct">{pct(s.share)}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>

      <p className="caption pie-foot">
        Your plan style decides whether extra debt payments or emergency savings come first.{" "}
        <button className="link" onClick={openStyle}>Compare plan styles</button>
      </p>
      {budget.totalCents !== budget.toPlanCents && (
        <p className="caption" style={{ marginTop: 6 }}>
          Essentials and minimums are more than the money available, so nothing else can be funded yet.
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
