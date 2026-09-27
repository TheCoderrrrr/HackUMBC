import { useEffect, useRef, useState, type ReactNode } from "react";
import { errorMessage } from "../api/client";
import type { PlanningPreference, Priority, StyleOutcome } from "../api/types";
import { Icon } from "../components/ui";
import { Term } from "../components/Term";
import type { TermId } from "../data/glossary";
import { monthLabel, percent } from "../data/format";
import { STYLE_INFO, STYLE_ORDER, outcomeFor, stylesDiffer } from "../data/styles";
import { useStore } from "../store";

const STEPS = 3;
const PRIORITY_TERM: Record<Priority, [string, TermId]> = {
  starter_reserve: ["One-month cushion", "cushion"],
  high_apr_debt: ["High-interest debt", "high-interest-debt"],
  full_reserve: ["Full emergency fund", "emergency-fund"],
};

/**
 * Getting started: a short introduction, the decision order, and a plan style choice.
 * Finishing applies the style and opens Your plan.
 */
export function Guide() {
  const { guideOpen, closeGuide, profile, style, setStyle, setTab, openPlan } = useStore();
  const [step, setStep] = useState(0);
  const [picked, setPicked] = useState<PlanningPreference>(style);
  const dialog = useRef<HTMLDivElement>(null);
  const returnFocus = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!guideOpen) return;
    setStep(0);
    setPicked(style);
    returnFocus.current = document.activeElement as HTMLElement | null;
    return () => returnFocus.current?.focus?.();
  }, [guideOpen, profile.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Move focus to the step's heading so screen readers announce it.
  useEffect(() => {
    if (guideOpen) dialog.current?.querySelector<HTMLElement>("h2")?.focus();
  }, [guideOpen, step]);

  const leave = (tab?: "learn") => {
    setStyle(style); // keep the current style; don't reopen for this profile
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

  const finish = () => {
    setStyle(picked);
    openPlan("style");
    closeGuide();
  };
  const first = profile.name.split(" ")[0];
  const next = () => setStep((s) => Math.min(s + 1, STEPS - 1));
  const back = () => setStep((s) => Math.max(s - 1, 0));

  const pages: { key: string; eyebrow?: string; title: string; body: ReactNode; primary: ReactNode }[] = [
    {
      key: "welcome", eyebrow: `Welcome, ${first}`, title: "A retirement plan that fits your real finances",
      body: <WelcomePage onLearn={() => leave("learn")} />,
      primary: <button className="btn-primary" onClick={next}>How it works <Icon name="arrow" /></button>,
    },
    {
      key: "how", eyebrow: "How ARM decides", title: "Your money goes out in a set order",
      body: <OrderPage />,
      primary: <button className="btn-primary" onClick={next}>Choose my style <Icon name="arrow" /></button>,
    },
    {
      key: "choose", eyebrow: "Your plan style", title: "Choose your plan style",
      body: <ChoosePage picked={picked} onPick={setPicked} current={style} name={first} />,
      primary: <button className="btn-primary" onClick={finish}>Use {STYLE_INFO[picked].label} and open my plan <Icon name="arrow" /></button>,
    },
  ];
  const page = pages[step];

  return (
    <>
      <div className="scrim" />
      <div ref={dialog} className="guide fade-in" role="dialog" aria-modal="true" aria-labelledby="guide-title">
        <div className="guide-progress" role="progressbar" aria-valuemin={1} aria-valuemax={STEPS} aria-valuenow={step + 1}
          aria-label={`Step ${step + 1} of ${STEPS}`} style={{ gridTemplateColumns: `repeat(${STEPS}, 1fr)` }}>
          {pages.map((p, i) => <i key={p.key} className={i <= step ? "on" : ""} />)}
        </div>
        <div className="guide-body" key={page.key}>
          <p className="eyebrow" style={{ padding: 0 }}>{page.eyebrow} · {step + 1} of {STEPS}</p>
          <h2 id="guide-title" className="guide-title" tabIndex={-1}>{page.title}</h2>
          {page.body}
          <div className="guide-foot">
            {step === 0 ? <button className="link" onClick={() => leave()}>Skip for now</button>
              : <button className="link" onClick={back}>Back</button>}
            {page.primary}
          </div>
        </div>
      </div>
    </>
  );
}

// ---------- Pages ----------

function WelcomePage({ onLearn }: { onLearn: () => void }) {
  return (
    <>
      <p className="body guide-lead">
        ARM helps you decide how to split extra money between an emergency cushion, expensive debt, and retirement saving.
        Choose a plan style to set the order that fits you.
      </p>
      <button className="guide-learn" onClick={onLearn}>
        <span className="guide-icon"><Icon name="learn" /></span>
        <span>
          <span className="strong" style={{ display: "block", fontSize: 15 }}>Explore lessons in Learn</span>
          <span className="caption" style={{ fontSize: 13 }}>Read more about the ideas behind your plan.</span>
        </span>
        <Icon name="chevron" />
      </button>
    </>
  );
}

/** The engine's waterfall in plain words; the saving target is read from the engine's assumptions. */
function OrderPage() {
  const { display } = useStore();
  const target = display?.evaluation.assumptions.retirement_total_saving_target;
  const steps: [ReactNode, string][] = [
    ["Essentials and minimum payments", "Rent, food, bills and every debt's minimum come first, always."],
    [<Term id="small-reserve">A small reserve</Term>, "A little cash so a minor surprise doesn't go on a card."],
    [<Term id="employer-match">The full employer match</Term>, "Free money from your employer, kept whenever you can afford it."],
    [<Term id="plan-style">Your plan style</Term>, "Decides the order of three goals: a cushion, expensive debt and a full emergency fund."],
    ["More retirement saving", target ? `Toward a combined saving rate of ${percent(target)} of pay.` : "Toward a healthy combined saving rate."],
    ["Anything left is yours", "Spend it, save it, or put it toward other goals."],
  ];
  return (
    <>
      <p className="body guide-lead">Each month, ARM covers these in order. You only choose step 4.</p>
      <ol className="guide-order">
        {steps.map(([title, text], i) => (
          <li key={i} className={i === 3 ? "yours" : ""}>
            <span className="guide-order-text"><b>{title}</b><span className="caption">{text}</span></span>
            {i === 3 && <span className="chip">You choose</span>}
          </li>
        ))}
      </ol>
    </>
  );
}

function ChoosePage({ picked, onPick, current, name }: {
  picked: PlanningPreference; onPick: (s: PlanningPreference) => void; current: PlanningPreference; name: string;
}) {
  return (
    <>
      <p className="body guide-lead">Pick the one that feels right. You can change it anytime from the sidebar.</p>
      <div className="guide-choose">
        <div className="style-options" role="radiogroup" aria-label="Plan styles">
          {STYLE_ORDER.map((s) => (
            <button key={s} role="radio" aria-checked={picked === s} className="style-option"
              style={{ ["--style" as string]: STYLE_INFO[s].color }} onClick={() => onPick(s)}>
              <span className="style-dot" />
              <span className="style-option-text">
                <span className="strong">{STYLE_INFO[s].label}</span>
                <span className="caption">{STYLE_INFO[s].tagline}</span>
              </span>
              {s === current && <span className="chip muted">Current</span>}
            </button>
          ))}
        </div>
        <StyleDetail style={picked} name={name} />
      </div>
    </>
  );
}

function StyleDetail({ style, name }: { style: PlanningPreference; name: string }) {
  const { planStyles, profile } = useStore();
  const info = STYLE_INFO[style];
  const outcome = planStyles.status === "loaded" ? outcomeFor(planStyles.data, style) : undefined;
  const same = planStyles.status === "loaded" && !stylesDiffer(planStyles.data);

  return (
    <div className="style-detail fade-in" key={style} style={{ ["--style" as string]: info.color }} aria-live="polite">
      <p className="style-detail-title">{info.label}</p>
      <p className="body style-detail-intro">{info.intro}</p>

      {outcome?.ordered_priorities && (
        <ol className="style-steps" aria-label="Where extra money goes, in order">
          {outcome.ordered_priorities.map((p) => (
            <li key={p}><Term id={PRIORITY_TERM[p][1]}>{PRIORITY_TERM[p][0]}</Term></li>
          ))}
        </ol>
      )}

      <div className="style-proscons">
        <div>
          <p className="style-pc-head good"><Icon name="check" size={14} /> Why people choose it</p>
          <p className="body">{info.pros}</p>
        </div>
        <div>
          <p className="style-pc-head bad"><Icon name="close" size={12} /> What you give up</p>
          <p className="body">{info.cons}</p>
        </div>
      </div>

      <div className="style-yours">
        <p className="eyebrow" style={{ padding: 0 }}>For {name}</p>
        {planStyles.status === "loading" && <p className="caption"><span className="spinner" /> Working out your numbers…</p>}
        {planStyles.status === "failed" && <p className="caption">{errorMessage(planStyles.error)}</p>}
        {planStyles.status === "idle" && <p className="caption">Turn on live calculation to see your numbers.</p>}
        {same && (
          <p className="caption style-same">
            All three styles give you the same result: there's no <Term id="high-interest-debt">high-interest debt</Term> to
            weigh against savings. Pick the one that matches how you think.
          </p>
        )}
        {outcome && !same && <Facts outcome={outcome} asOf={profile.as_of_date} />}
      </div>
    </div>
  );
}

function when(month: number | null, asOf: string, done: string, never: string): string {
  if (month === null) return never;
  return month === 0 ? done : monthLabel(asOf, month);
}

function Facts({ outcome, asOf }: { outcome: StyleOutcome; asOf: string }) {
  return (
    <dl className="style-facts">
      <div><dt>Debt-free</dt><dd>{when(outcome.debt_free_month, asOf, "No debt", "After retirement")}</dd></div>
      <div><dt>Emergency fund full</dt><dd>{when(outcome.full_reserve_month, asOf, "Already", "Not reached")}</dd></div>
    </dl>
  );
}
