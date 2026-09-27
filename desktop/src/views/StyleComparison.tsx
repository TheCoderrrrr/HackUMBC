import { useMemo, type ReactNode } from "react";
import { errorMessage } from "../api/client";
import type { PlanStyles, StyleOutcome } from "../api/types";
import { LineChart, type Series } from "../components/LineChart";
import { Term } from "../components/Term";
import { money, monthLabel, when } from "../data/format";
import { PRIORITY_LABEL, STYLE_INFO, STYLE_ORDER, stylesDiffer } from "../data/styles";
import { useStore } from "../store";

const CURRENT_COLOR = "var(--blue)";


const cents = (v: number | null) => (v === null ? "–" : money(v));

/**
 * "How your plan style compares": current habits and the three styles on one chart and table,
 * the chosen style highlighted. Every number comes from /v1/plan-styles.
 */
export function StyleComparison() {
  const { planStyles, style, profile, liveEnabled } = useStore();

  return (
    <section aria-labelledby="styles-title">
      <h2 id="styles-title" className="h-section" tabIndex={-1}>How the three styles compare</h2>
      <p className="subtitle">
        Projected retirement balance by year · you're on{" "}
        <span style={{ color: STYLE_INFO[style].color, fontWeight: 500 }}>{STYLE_INFO[style].label}</span>
      </p>

      {planStyles.status === "idle" && (
        <p className="body state-note">{liveEnabled ? "Loading…" : "Turn on live calculation to compare plan styles on your numbers."}</p>
      )}
      {planStyles.status === "loading" && <p className="caption state-note"><span className="spinner" /> Calculating…</p>}
      {planStyles.status === "failed" && <p className="body state-note">{errorMessage(planStyles.error)}</p>}
      {planStyles.status === "loaded" && <Loaded data={planStyles.data} name={profile.name.split(" ")[0]} age={profile.age} />}
    </section>
  );
}

/** Shown when the live AI decision ordered priorities differently from the chosen style's rule. */
function AiOverride({ data }: { data: PlanStyles }) {
  const { style, display, setDrawer } = useStore();
  const decision = display?.evaluation.decision_summary;
  const expected = data.styles.find((s) => s.style === style)?.ordered_priorities;
  if (!decision || decision.source !== "ai" || !expected || decision.ordered_priorities.join() === expected.join()) return null;
  return (
    <p className="guide-callout" style={{ marginTop: 16 }}>
      Your monthly plan uses an AI-chosen order ({decision.ordered_priorities.map((p) => PRIORITY_LABEL[p]).join(" → ")}),
      not {STYLE_INFO[style].label}'s usual one. The chart below follows the {STYLE_INFO[style].label} rule.{" "}
      <button className="link" onClick={() => setDrawer("explanation")}>See why</button>
    </p>
  );
}

function Loaded({ data, name, age }: { data: PlanStyles; name: string; age: number }) {
  const { style } = useStore();
  const differ = stylesDiffer(data);
  const outcomes = STYLE_ORDER.map((s) => data.styles.find((o) => o.style === s)).filter((o): o is StyleOutcome => Boolean(o));
  // When styles don't differ, one line stands for all three.
  const shown = differ ? outcomes : outcomes.filter((o) => o.style === style);

  const series = useMemo<Series[]>(() => [
    { name: data.current.label, values: data.current.yearly.map((y) => y.retirement_balance_cents), color: CURRENT_COLOR, dashed: true, width: 2 },
    // Others first, so the chosen style draws on top.
    ...[...shown.filter((o) => o.style !== style), ...shown.filter((o) => o.style === style)].map((o) => ({
      name: o.label, values: o.yearly.map((y) => y.retirement_balance_cents), color: STYLE_INFO[o.style!].color,
      area: o.style === style, width: o.style === style ? 2.6 : 1.6,
    })),
  ], [data, shown, style]);

  const startYear = Number(data.as_of_date.slice(0, 4));
  const span = Math.max(...series.map((s) => s.values.length - 1), 0);
  const columns: StyleOutcome[] = [data.current, ...shown];
  const rows: [ReactNode, (o: StyleOutcome) => string][] = [
    ["Debt-free (all debts)", (o) => when(o.debt_free_month, data.as_of_date, "None", "After retirement")],
    [<Term id="emergency-fund">Emergency fund full</Term>, (o) => when(o.full_reserve_month, data.as_of_date, "Already", "Not reached")],
    ["Debt interest paid", (o) => cents(o.cumulative_debt_interest_cents)],
    [`Balance at ${data.current.retirement_age}`, (o) => cents(o.retirement_balance_nominal_cents)],
    [<Term id="todays-dollars">In today's dollars</Term>, (o) => cents(o.retirement_balance_today_cents)],
  ];

  return (
    <div className="fade-in">
      <AiOverride data={data} />
      {!differ && (
        <p className="guide-callout" style={{ marginTop: 16 }}>
          For {name}, all three styles give the same result: there's no <Term id="high-interest-debt">high-interest debt</Term> to
          weigh against savings.
        </p>
      )}
      <div className="legend" style={{ margin: "18px 0 36px", flexWrap: "wrap" }}>
        {series.map((s) => (
          <span key={s.name} style={{ color: s.color, fontWeight: s.area ? 600 : 400 }}>
            <i className={s.dashed ? "dashed" : ""} />
            {s.dashed ? <Term id="current-habits">{s.name}</Term> : s.name}{s.area ? " (yours)" : ""}
          </span>
        ))}
      </div>
      <LineChart height={220} series={series} renderTooltip={(i) => (
        <div style={{ display: "grid", gap: 3 }}>
          <span>{monthLabel(data.as_of_date, 12 * i)} · Age {age + i}</span>
          {series.map((s) => s.values[i] !== undefined && (
            <span key={s.name}>{s.name} <b style={{ color: s.color }}>{money(s.values[i])}</b></span>
          ))}
        </div>
      )} />
      <div className="axis">
        <span>{startYear}</span>
        <span>{startYear + Math.round(span / 2)}</span>
        <span>{startYear + span} · Age {age + span}</span>
      </div>

      <table className="table style-table" style={{ marginTop: 22 }}>
        <thead>
          <tr>
            <th scope="col"><span className="sr-only">Measure</span></th>
            {columns.map((o) => (
              <th scope="col" key={o.label} className={o.style === style ? "chosen" : ""}
                style={{ color: o.style ? STYLE_INFO[o.style].color : CURRENT_COLOR }}>
                {differ || !o.style ? o.label : "Any style"}
                {o.style === style && differ && <span className="chip" style={{ marginLeft: 6 }}>Yours</span>}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map(([title, value], i) => (
            <tr key={i}>
              <th scope="row" className="label">{title}</th>
              {columns.map((o) => <td key={o.label} className={o.style === style ? "chosen" : ""}>{value(o)}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="caption" style={{ marginTop: 14 }}>
        A <Term id="projection">projection</Term> using each style's own priority order and the same illustrative
        assumptions (model {data.model_version}). Not a forecast or guarantee.
      </p>
    </div>
  );
}
