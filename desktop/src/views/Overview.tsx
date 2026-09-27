import type { ReactNode } from "react";
import { Icon } from "../components/ui";
import { Disclosure } from "../components/Tabs";
import { Term } from "../components/Term";
import { DISCLOSURE, type Display } from "../data/display";
import { asOfLabel, money, moneyExact, months, percent } from "../data/format";
import { STYLE_INFO } from "../data/styles";
import { useStore, type PlanSection } from "../store";

/**
 * Overview: where you are today and the one thing to do next. Details live one click away in
 * Your plan; the chart lives there too, so nothing is shown twice.
 */
export function Overview({ display }: { display: Display }) {
  const { openPlan, setTab, setDrawer } = useStore();
  const { profile, evaluation } = display;
  const { adaptive, current } = evaluation.projections;
  const debtTotal = display.debts.reduce((s, d) => s + d.balanceCents, 0);
  const costliest = [...display.debts].sort((a, b) => b.apr - a.apr)[0];

  return (
    <div className="grid overview fade-in" key={profile.id}>
      <div className="stack">
        <section className="glass tint-green card next-step" aria-labelledby="next-title">
          <p className="eyebrow" style={{ padding: 0 }}>Your next step</p>
          <h2 id="next-title" className="next-step-title">{display.nextStep.headline}</h2>
          <p className="body" style={{ marginTop: 8, fontSize: 15 }}>
            {display.nextStep.amountCents !== null && <span className="strong num">{moneyExact(display.nextStep.amountCents)}</span>}
            {display.nextStep.detail}
          </p>
          <div className="next-step-actions">
            <button className="btn-primary" onClick={() => openPlan("month")}>See this month's plan <Icon name="arrow" /></button>
            <button className="pill neutral" onClick={() => setDrawer({ why: "month" })}><Icon name="why" /> Why this step?</button>
          </div>
        </section>

        <section aria-labelledby="glance-title">
          <h2 id="glance-title" className="h-card" style={{ marginBottom: 12 }}>At a glance</h2>
          <div className="glance">
            <Tile section="saving" label="Retirement savings" value={money(profile.retirement_balance_cents)}
              sub={`${percent(display.rate)} of pay going in`} />
            <Tile section="emergency" label={<Term id="emergency-fund">Emergency fund</Term>} value={months(display.emergencyMonths)}
              sub={`Target: ${display.fullMonths} months`} />
            {display.debts.length > 0 ? (
              <Tile section="debt" label="Debt" value={money(debtTotal)} sub={`Highest rate ${percent(costliest.apr)} APR`} />
            ) : (
              <Tile section="month" label="Debt" value="None" sub="Nothing to pay down" />
            )}
          </div>
        </section>

        <button className="section heading-card" onClick={() => setTab("plan")}>
          <span>
            <span className="eyebrow" style={{ padding: 0 }}>Where you're heading</span>
            <span className="heading-figure num">{money(adaptive.retirement_balance_nominal_cents ?? 0)}</span>
            <span className="body" style={{ fontSize: 14 }}>
              projected at age {profile.retirement_age}, compared with {money(current.retirement_balance_nominal_cents ?? 0)} on current habits
            </span>
          </span>
          <span className="heading-cta">See your projection <Icon name="chevron" size={14} /></span>
        </button>
      </div>

      <aside className="stack">
        <FirstSteps />
        <Disclosure title="Details" summary="Your numbers and the model's assumptions">
          <LinkRow icon="doc" title="Financial snapshot" onClick={() => setDrawer("snapshot")} />
          <hr className="hairline" />
          <LinkRow icon="sliders" title="Modeling assumptions" onClick={() => setDrawer("assumptions")} />
          <p className="caption" style={{ marginTop: 12 }}>
            {display.origin} · as of {asOfLabel(profile.as_of_date)} · {DISCLOSURE.fictional}
          </p>
        </Disclosure>
      </aside>
    </div>
  );
}

/** One figure with its context; the arrow opens that topic in Your plan. */
function Tile({ section, label, value, sub }: { section: PlanSection; label: ReactNode; value: string; sub: string }) {
  const { openPlan } = useStore();
  return (
    <div className="tile">
      <span className="tile-top">
        <span className="tile-label">{label}</span>
        <button className="tile-open" onClick={() => openPlan(section)} aria-label="Open in Your plan" title="Open in Your plan">
          <Icon name="chevron" size={13} />
        </button>
      </span>
      <span className="tile-value num">{value}</span>
      <span className="tile-sub">{sub}</span>
    </div>
  );
}

/** A short guided path for first-time users. Every step looks the same; a finished one gets a small check. */
function FirstSteps() {
  const { styleChosen, style, openStyle, openPlan, setTab } = useStore();
  const steps: { title: string; sub: string; done?: boolean; run: () => void }[] = [
    { title: "Choose a plan style", sub: styleChosen ? `On ${STYLE_INFO[style].label}` : "Takes a minute", done: styleChosen, run: openStyle },
    { title: "Review this month's money", sub: "Where each dollar goes", run: () => openPlan("month") },
    { title: "See where you're heading", sub: "Your balance at any age", run: () => setTab("plan") },
    { title: "Learn the basics", sub: "Six short lessons", run: () => setTab("learn") },
  ];
  return (
    <section className="section first-steps" aria-labelledby="steps-title">
      <h2 id="steps-title" className="h-card">Your first steps</h2>
      <ol>
        {steps.map((s, i) => (
          <li key={s.title}>
            <button onClick={s.run}>
              <span className="fs-num" aria-hidden="true">{i + 1}</span>
              <span className="fs-text"><b>{s.title}</b><span className="caption">{s.sub}</span></span>
              {s.done ? <span className="fs-done" role="img" aria-label="Done"><Icon name="check" size={12} /></span> : <Icon name="chevron" size={13} />}
            </button>
          </li>
        ))}
      </ol>
    </section>
  );
}

function LinkRow({ icon, title, onClick }: { icon: string; title: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="link-row">
      <Icon name={icon} size={16} /> {title}
      <span style={{ marginLeft: "auto", display: "flex" }}><Icon name="chevron" size={15} /></span>
    </button>
  );
}
