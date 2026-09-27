import type { ReactNode } from "react";
import type { PlanningPreference } from "../api/types";
import { Icon } from "../components/ui";
import { Term } from "../components/Term";
import type { Display } from "../data/display";
import { money, months, percent } from "../data/format";
import { STYLE_INFO } from "../data/styles";
import { useStore } from "../store";

interface Lesson {
  id: string;
  icon: string;
  title: string;
  body: ReactNode;
  yours: ReactNode;
  action: { label: string; run: () => void } | { disabled: string };
}

/**
 * Learn: the ideas behind the plan, one short lesson each. "Apply" changes one real input (a
 * scenario or the plan style) and opens the result. Every number is the profile's own or the engine's.
 */
export function Learn({ display }: { display: Display }) {
  const { setTab, setPendingScenario, setStyle, style, openStyle } = useStore();
  const { profile, evaluation } = display;
  const a = evaluation.assumptions;
  const fullMatchRate = evaluation.financial_state.employee_rate_for_full_match;
  const costliest = display.debts.filter((d) => d.apr >= a.high_interest_apr_threshold).sort((x, y) => y.apr - x.apr)[0];
  const laterAge = Math.min(profile.retirement_age + 2, 80);

  const showStyles = (next?: PlanningPreference) => {
    if (next) setStyle(next);
    setTab("plan");
    openStyle();
  };
  const tryScenario = (retirementAge: number, rate: number | null) => {
    setPendingScenario({ retirement_age: retirementAge, employee_contribution_rate: rate });
    setTab("explore");
  };
  const styleAction = (target: PlanningPreference) =>
    style === target ? { label: "See it in your plan", run: () => showStyles() }
      : { label: `Try ${STYLE_INFO[target].label}`, run: () => showStyles(target) };

  const lessons: Lesson[] = [
    {
      id: "match", icon: "seal", title: "Get the full employer match",
      body: <>Your <Term id="employer-match">employer match</Term> is money added for free when you contribute. Missing
        any of it is like turning down part of your pay.</>,
      yours: fullMatchRate === null ? "No confirmed employer match on your profile."
        : <>You contribute <b>{percent(display.currentRate)}</b>; the full match needs <b>{percent(fullMatchRate)}</b>.</>,
      action: fullMatchRate === null ? { disabled: "No match to apply" }
        : { label: `Try ${percent(fullMatchRate)}`, run: () => tryScenario(profile.retirement_age, fullMatchRate) },
    },
    {
      id: "time", icon: "replay", title: "Give money time to grow",
      body: <>With <Term id="compound-growth">compound growth</Term>, each extra year invested adds more than the one
        before it.</>,
      yours: <>You plan to retire at <b>{profile.retirement_age}</b>, in {display.yearsToRetirement} years.</>,
      action: laterAge === profile.retirement_age ? { disabled: "Already at the latest age" }
        : { label: `Try retiring at ${laterAge}`, run: () => tryScenario(laterAge, null) },
    },
    {
      id: "debt", icon: "flag", title: "Clear expensive debt early",
      body: <>Paying down <Term id="high-interest-debt">high-interest debt</Term> is a guaranteed return equal to
        its <Term id="apr">APR</Term>, often more than investing can reliably earn.</>,
      yours: costliest ? <>{costliest.name}: <b>{money(costliest.balanceCents)}</b> at <b>{percent(costliest.apr)}</b> APR.</>
        : "You have no high-interest debt.",
      action: styleAction("debt_reduction"),
    },
    {
      id: "emergency", icon: "umbrella", title: "Keep an emergency fund",
      body: <>An <Term id="emergency-fund">emergency fund</Term> keeps a surprise bill from turning into new debt. ARM
        builds a <Term id="cushion">one-month cushion</Term> first.</>,
      yours: <>You have <b>{months(display.emergencyMonths)}</b> saved; the full target is {display.fullMonths} months.</>,
      action: styleAction("cash_security"),
    },
    {
      id: "inflation", icon: "sliders", title: "Read future balances in today's dollars",
      body: <>Prices rise over time, so compare big future numbers in <Term id="todays-dollars">today's dollars</Term>.</>,
      yours: <>The model assumes <b>{percent(a.annual_inflation)}</b> inflation a year.</>,
      action: { label: "Compare in your plan", run: () => showStyles() },
    },
    {
      id: "glide", icon: "building", title: "Know what your fund does",
      body: <>A <Term id="target-date-fund">target-date fund</Term> follows a <Term id="glide-path">glide path</Term>:
        more stocks early, more bonds near retirement. ARM leaves it as it is.</>,
      yours: <>Your fund holds about <b>{percent(display.equityWeight)}</b> stocks today.</>,
      action: { label: "Compare funds", run: () => setTab("funds") },
    },
  ];

  return (
    <div className="learn fade-in">
      <div className="learn-intro">
        <p className="body">Six ideas behind your plan. <b className="strong">Try</b> applies one to your own numbers.</p>
        <button className="pill neutral" onClick={openStyle}><Icon name="compare" /> Choose a plan style</button>
      </div>
      <div className="learn-grid">
        {lessons.map((l) => (
          <article key={l.id} className="section lesson" aria-labelledby={`lesson-${l.id}`}>
            <span className="guide-icon"><Icon name={l.icon} /></span>
            <h2 id={`lesson-${l.id}`} className="h-section lesson-title">{l.title}</h2>
            <p className="body lesson-body">{l.body}</p>
            <p className="lesson-yours"><Icon name="person" size={14} /><span>{l.yours}</span></p>
            {"run" in l.action ? (
              <button className="pill selected lesson-apply" onClick={l.action.run}>{l.action.label} <Icon name="arrow" /></button>
            ) : (
              <p className="caption lesson-apply">{l.action.disabled}</p>
            )}
          </article>
        ))}
      </div>
    </div>
  );
}
