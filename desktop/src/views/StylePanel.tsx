import { errorMessage } from "../api/client";
import type { PlanningPreference, Priority, StyleOutcome } from "../api/types";
import { Drawer, Icon } from "../components/ui";
import { Term } from "../components/Term";
import type { TermId } from "../data/glossary";
import { monthLabel } from "../data/format";
import { STYLE_INFO, STYLE_ORDER, outcomeFor, stylesDiffer } from "../data/styles";
import { useStore } from "../store";
import { StyleComparison } from "./StyleComparison";

const PRIORITY_TERM: Record<Priority, [string, TermId]> = {
  starter_reserve: ["One-month cushion", "cushion"],
  high_apr_debt: ["High-interest debt", "high-interest-debt"],
  full_reserve: ["Full emergency fund", "emergency-fund"],
};

/**
 * Plan style: pick one of the three styles (applied at once, switch anytime), see what it means
 * for this person, and compare all three on one chart. Opened from Your plan and the sidebar.
 */
export function StylePanel() {
  const { styleOpen, closeStyle, style, setStyle, profile } = useStore();
  if (!styleOpen) return null;
  const first = profile.name.split(" ")[0];

  return (
    <Drawer wide title="Plan style" onClose={closeStyle}
      subtitle="Sets the order of three goals: a cushion, expensive debt and a full emergency fund. Switch anytime."
      footer={<button className="btn-primary full" onClick={closeStyle}>Use {STYLE_INFO[style].label}</button>}>
      <div className="style-picker" role="radiogroup" aria-label="Plan styles">
        {STYLE_ORDER.map((s) => (
          <button key={s} role="radio" aria-checked={style === s} className="style-option"
            style={{ ["--style" as string]: STYLE_INFO[s].color }} onClick={() => setStyle(s)}>
            <span className="style-dot" />
            <span className="style-option-text">
              <span className="strong">{STYLE_INFO[s].label}</span>
              <span className="caption">{STYLE_INFO[s].tagline}</span>
            </span>
            {style === s && <Icon name="check" size={16} />}
          </button>
        ))}
      </div>
      <StyleDetail style={style} name={first} />
      <hr className="hairline" style={{ margin: "26px 0 22px" }} />
      <StyleComparison />
    </Drawer>
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
            All three styles give the same result: there's no <Term id="high-interest-debt">high-interest debt</Term> to
            weigh against savings.
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
