import { useEffect, useRef, useState, type ReactNode } from "react";
import { Icon } from "../components/ui";
import { Term } from "../components/Term";
import { percent } from "../data/format";
import { useStore } from "../store";

const STEPS = 2;

/**
 * Getting started (a modal dialog, shown once per browser and anytime from the sidebar): a short
 * introduction and the decision order. Every page can be skipped. The plan style is chosen
 * separately, from the Plan style button in Your plan or the sidebar menu.
 */
export function Guide() {
  const { guideOpen, closeGuide, profile, setTab } = useStore();
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

  const leave = (tab?: "learn" | "plan") => {
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
      key: "welcome", eyebrow: `Welcome, ${first}`, title: "A retirement plan that fits your real finances",
      body: <WelcomePage onLearn={() => leave("learn")} />,
      primary: <button className="btn-primary" onClick={next}>How it works <Icon name="arrow" /></button>,
    },
    {
      key: "how", eyebrow: "How ARM decides", title: "Your money goes out in a set order",
      body: <OrderPage />,
      primary: <button className="btn-primary" onClick={() => leave("plan")}>Open my plan <Icon name="arrow" /></button>,
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

// ---------- Pages ----------

function WelcomePage({ onLearn }: { onLearn: () => void }) {
  return (
    <>
      <p className="body guide-lead">
        ARM helps you decide how to split extra money between an emergency cushion, expensive debt, and retirement saving.
        You set that order with the <b className="strong">Plan style</b> button in Your plan, and can switch anytime.
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
      <p className="body guide-lead">Each month, ARM covers these in order. You only choose step 4, with the Plan style button.</p>
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
