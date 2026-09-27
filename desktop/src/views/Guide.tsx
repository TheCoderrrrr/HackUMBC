import { useEffect, useRef, useState } from "react";
import { errorMessage } from "../api/client";
import type { PlanningPreference, Priority, StyleOutcome } from "../api/types";
import { Icon } from "../components/ui";
import { Term } from "../components/Term";
import type { TermId } from "../data/glossary";
import { monthLabel } from "../data/format";
import { STYLE_INFO, STYLE_ORDER, outcomeFor, stylesDiffer } from "../data/styles";
import { useStore } from "../store";

const STEPS = 2;
const PRIORITY_TERM: Record<Priority, [string, TermId]> = {
  starter_reserve: ["One-month cushion", "cushion"],
  high_apr_debt: ["High-interest debt", "high-interest-debt"],
  full_reserve: ["Full emergency fund", "emergency-fund"],
};

/**
 * First-open guide (a modal dialog). Step 1: what ARM does, with a way into Learn. Step 2: one
 * plan style at a time in plain words, with two of the person's own numbers. Choosing a style
 * opens Your plan at the comparison. The priority order shown comes from the backend.
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

  const choose = () => {
    setStyle(picked);
    openPlan("style");
    closeGuide();
  };
  const first = profile.name.split(" ")[0];

  return (
    <>
      <div className="scrim" />
      <div ref={dialog} className="guide fade-in" role="dialog" aria-modal="true" aria-labelledby="guide-title">
        <div className="guide-progress" role="progressbar" aria-valuemin={1} aria-valuemax={STEPS} aria-valuenow={step + 1}
          aria-label={`Step ${step + 1} of ${STEPS}`}>
          {Array.from({ length: STEPS }, (_, i) => <i key={i} className={i <= step ? "on" : ""} />)}
        </div>

        {step === 0 ? (
          <div className="guide-body" key="welcome">
            <p className="eyebrow" style={{ padding: 0 }}>Welcome, {first}</p>
            <h2 id="guide-title" className="guide-title" tabIndex={-1}>A retirement plan that fits your real finances</h2>
            <p className="body guide-lead">
              ARM keeps your <Term id="target-date-fund">target-date fund</Term> exactly as it is. It adapts how much you
              save and where each extra dollar goes. Pick a <Term id="plan-style">plan style</Term> next, and we'll show
              what it means for your money.
            </p>
            <button className="guide-learn" onClick={() => leave("learn")}>
              <span className="guide-icon"><Icon name="learn" /></span>
              <span>
                <span className="strong" style={{ display: "block", fontSize: 15 }}>New to this? Start in Learn</span>
                <span className="caption" style={{ fontSize: 13 }}>Five-minute lessons on the ideas behind your plan. Choose a style later from the sidebar.</span>
              </span>
              <Icon name="chevron" />
            </button>
            <div className="guide-foot">
              <button className="link" onClick={() => leave()}>Skip for now</button>
              <button className="btn-primary" onClick={() => setStep(1)}>Compare plan styles <Icon name="arrow" /></button>
            </div>
          </div>
        ) : (
          <div className="guide-body" key="choose">
            <h2 id="guide-title" className="guide-title" tabIndex={-1} style={{ marginTop: 0 }}>Choose your plan style</h2>
            <p className="body guide-lead">
              Your essentials, minimum payments, a <Term id="small-reserve">small reserve</Term> and the
              full <Term id="employer-match">employer match</Term> always come first. A style decides what your extra
              money does next.
            </p>
            <div className="guide-choose">
              <div className="style-options" role="radiogroup" aria-label="Plan styles">
                {STYLE_ORDER.map((s) => (
                  <button key={s} role="radio" aria-checked={picked === s} className="style-option"
                    style={{ ["--style" as string]: STYLE_INFO[s].color }} onClick={() => setPicked(s)}>
                    <span className="style-dot" />
                    <span className="style-option-text">
                      <span className="strong">{STYLE_INFO[s].label}</span>
                      <span className="caption">{STYLE_INFO[s].tagline}</span>
                    </span>
                    {s === style && <span className="chip muted">Current</span>}
                  </button>
                ))}
              </div>
              <StyleDetail style={picked} name={first} />
            </div>
            <div className="guide-foot">
              <button className="link" onClick={() => setStep(0)}>Back</button>
              <button className="btn-primary" onClick={choose}>Use {STYLE_INFO[picked].label} <Icon name="arrow" /></button>
            </div>
          </div>
        )}
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
      <div><dt>High-interest debt paid off</dt><dd>{when(outcome.debt_free_month, asOf, "No debt", "After retirement")}</dd></div>
      <div><dt>Emergency fund full</dt><dd>{when(outcome.full_reserve_month, asOf, "Already", "Not reached")}</dd></div>
    </dl>
  );
}
