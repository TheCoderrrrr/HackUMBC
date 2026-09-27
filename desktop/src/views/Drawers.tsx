import type { ReactNode } from "react";
import { Drawer, Icon } from "../components/ui";
import { debtName, explanationSteps, PRIORITY_LABEL, type Display } from "../data/display";
import { asOfLabel, money, moneyExact, months, percent } from "../data/format";
import { usesBundle } from "../data/saved";
import { useStore } from "../store";

const CHECK_LABEL: Record<string, string> = {
  EXACT_PRIORITY_MEMBERSHIP: "Priorities are exactly the documented set",
  STARTER_BEFORE_FULL_RESERVE: "Starter reserve comes before the full reserve",
  SUPPORTED_PREFERENCE_ORDER: "Priority order is a documented option",
  EVIDENCE_VALIDATED: "Every reason cites real inputs",
  ESSENTIALS_AND_MATCH_PROTECTED: "Essentials and employer match protected",
};

const FALLBACK_LABEL: Record<string, string> = {
  AI_UNAVAILABLE: "AI is not configured on this server",
  TIMEOUT: "AI took too long",
  PROVIDER_ERROR: "AI provider error",
  RATE_LIMITED: "AI rate limit reached",
  AI_COOLDOWN: "AI cooling down after errors",
  NO_AI_PROPOSAL: "AI returned no proposal",
  BLOCKED_FINANCIAL_INPUT: "Inputs need attention before AI can help",
  INVALID_PRIORITY_ORDER: "AI proposed an invalid order",
  INVALID_EVIDENCE: "AI cited invalid evidence",
  UNSUPPORTED_RATIONALE_CLAIM: "AI made an unsupported claim",
};

export function Drawers({ display }: { display: Display }) {
  const { drawer, setDrawer } = useStore();
  const close = () => setDrawer(null);
  if (drawer === "explanation") return <Explanation display={display} onClose={close} />;
  if (drawer === "snapshot") return <Snapshot display={display} onClose={close} />;
  if (drawer === "assumptions") return <Assumptions display={display} onClose={close} />;
  return null;
}

function Explanation({ display, onClose }: { display: Display; onClose: () => void }) {
  const { evaluation, profile } = display;
  const summary = evaluation.decision_summary;
  const paying = display.debts.find((d) => d.extraCents > 0);
  const headline = paying ? "Keep your match. Reduce costly debt." : display.nextStep.headline;
  const tradeoff = summary.rationale.find((r) => r.priority === summary.ordered_priorities[0])?.tradeoff;

  return (
    <Drawer title="Why this plan?" onClose={onClose}
      footer={<button className="btn-primary full" onClick={onClose}>Got it</button>}>
      <p style={{ fontSize: 24, fontWeight: 400, lineHeight: 1.3, marginTop: 12 }}>{headline}</p>
      <p className="body" style={{ marginTop: 12 }}>
        {evaluation.explanation.source === "ai" ? evaluation.explanation.narrative : evaluation.explanation.state_summary}
      </p>

      <div style={{ display: "grid", gap: 22, margin: "24px 0" }}>
        {explanationSteps(display).map((step, i) => (
          <div key={step.title} style={{ display: "flex", gap: 14 }}>
            <span className="step-num">{i + 1}</span>
            <div>
              <p style={{ fontSize: 17, fontWeight: 500 }}>{step.title}</p>
              <p className="body" style={{ fontSize: 14, marginTop: 4 }}>{step.detail}</p>
            </div>
          </div>
        ))}
      </div>
      <hr className="hairline strong" />

      <Title>Priority order</Title>
      <div style={{ display: "grid", gap: 12 }}>
        {summary.ordered_priorities.map((p, i) => {
          const rationale = summary.rationale.find((r) => r.priority === p);
          return (
            <div key={p}>
              <p style={{ fontSize: 15, fontWeight: 500 }}><span style={{ color: "var(--accent)" }}>{i + 1}.</span> {PRIORITY_LABEL[p]}</p>
              {rationale && <p className="body" style={{ fontSize: 13, marginTop: 2 }}>{rationale.summary}</p>}
            </div>
          );
        })}
      </div>

      {(tradeoff || display.rate !== display.currentRate) && (
        <>
          <hr className="hairline strong" style={{ marginTop: 22 }} />
          <Title>The tradeoff</Title>
          <p className="body">
            {display.rate !== display.currentRate
              ? `Your contribution moves from ${percent(display.currentRate)} to ${percent(display.rate)} for now. ${tradeoff ?? ""}`
              : tradeoff}
          </p>
        </>
      )}

      <hr className="hairline strong" style={{ marginTop: 22 }} />
      <Title>Checks</Title>
      {summary.constraint_checks.map((c) => (
        <div key={c.code} className="row" style={{ minHeight: 34 }}>
          <span className="title" style={{ fontSize: 14 }}>{CHECK_LABEL[c.code] ?? c.code.replaceAll("_", " ").toLowerCase()}</span>
          <span style={{ color: c.passed ? "var(--accent)" : "#d98b7a", display: "flex" }}>
            {c.passed ? <Icon name="check" size={16} /> : <Icon name="close" size={16} />}
          </span>
        </div>
      ))}

      <hr className="hairline strong" style={{ marginTop: 18 }} />
      <Title>Supporting inputs</Title>
      <Row label="Gross salary" value={`${money(profile.annual_gross_salary_cents)} /yr`} />
      {profile.debts.map((d) => (
        <div key={d.id}>
          <Row label={`${debtName(d.type)} balance`} value={money(d.balance_cents)} />
          <Row label={`${debtName(d.type)} APR`} value={percent(d.apr)} />
        </div>
      ))}
      {profile.debts.length === 0 && <Row label="Retirement balance" value={money(profile.retirement_balance_cents)} />}
      <Row label="Emergency cash" value={money(profile.emergency_cash_cents)} />

      <p className="caption" style={{ marginTop: 16 }}>
        {display.origin}
        {summary.fallback_reason && ` · ${FALLBACK_LABEL[summary.fallback_reason] ?? summary.fallback_reason}`}
        <br />As of {asOfLabel(profile.as_of_date)} · model {evaluation.model_version} · policy {evaluation.policy_version}
      </p>
    </Drawer>
  );
}

function Snapshot({ display, onClose }: { display: Display; onClose: () => void }) {
  const { profile, evaluation } = display;
  const state = evaluation.financial_state;
  return (
    <Drawer title="Financial snapshot" subtitle={`${profile.name} · as of ${asOfLabel(profile.as_of_date)}`} onClose={onClose}>
      <Title first>Income</Title>
      <Row label="Gross salary" value={`${money(profile.annual_gross_salary_cents)} /yr`} />
      <Row label="Take-home pay" value={`${moneyExact(profile.monthly_take_home_cents)} /mo`} />
      <Row label="Living expenses" value={`${moneyExact(profile.monthly_living_expenses_cents)} /mo`} />
      <Row label="Resources before contributions" value={`${moneyExact(state.monthly_resources_before_retirement_cents)} /mo`} />

      <Title>Retirement</Title>
      <Row label="Balance" value={money(profile.retirement_balance_cents)} />
      <Row label="Contribution today" value={`${percent(profile.employee_contribution_rate)} · ${moneyExact(state.current_employee_contribution_cents)} /mo`} />
      <Row label="Rate for full match" value={state.employee_rate_for_full_match === null ? "No match" : percent(state.employee_rate_for_full_match)} />
      <Row label="Tax treatment" value={profile.contribution_tax_treatment === "roth" ? "Roth" : "Traditional"} />
      <Row label="Age · retirement age" value={`${profile.age} · ${profile.retirement_age}`} />

      <Title>Cash and debt</Title>
      <Row label="Emergency cash" value={`${money(profile.emergency_cash_cents)} · ${months(state.emergency_months)}`} />
      {profile.debts.map((d) => (
        <Row key={d.id} label={`${debtName(d.type)} · ${percent(d.apr)} APR`} value={`${money(d.balance_cents)} · min ${money(d.minimum_payment_cents)}`} />
      ))}
      {profile.debts.length === 0 && <Row label="Debts" value="None" />}

      <p className="caption" style={{ marginTop: 18 }}>
        Fictional customer · synthetic data. {usesBundle ? "Saved results from the demo bundle." : "Saved results from the contract examples."}
      </p>
    </Drawer>
  );
}

function Assumptions({ display, onClose }: { display: Display; onClose: () => void }) {
  const { liveEnabled, setLiveEnabled, connection, health, checkConnection } = useStore();
  const a = display.evaluation.assumptions;
  return (
    <Drawer title="Modeling assumptions" subtitle="Illustrative, nominal, net of fees" onClose={onClose}>
      <Title first>Returns and growth</Title>
      <Row label="Stocks" value={`${percent(a.annual_equity_return)} /yr`} />
      <Row label="Bonds" value={`${percent(a.annual_bond_return)} /yr`} />
      <Row label="Cash" value={`${percent(a.annual_cash_return)} /yr`} />
      <Row label="Inflation" value={`${percent(a.annual_inflation)} /yr`} />
      <Row label="Salary growth" value={`${percent(a.annual_salary_growth)} /yr`} />
      <Row label="Living-cost growth" value={`${percent(a.annual_living_cost_growth)} /yr`} />

      <Title>Planning targets</Title>
      <Row label="High-interest APR threshold" value={percent(a.high_interest_apr_threshold)} />
      <Row label="Combined saving target" value={percent(a.retirement_total_saving_target)} />
      <Row label="Starter · full reserve" value={`${a.starter_reserve_months} · ${a.full_reserve_months} months`} />

      <Title>Glide path</Title>
      {a.glide_path.map((g) => (
        <Row key={g.years_to_retirement} label={`${g.years_to_retirement} years to retirement`} value={`${percent(g.equity_weight)} stocks`} />
      ))}

      <Title>Limitations</Title>
      <ul className="body" style={{ fontSize: 13, paddingLeft: 18, margin: 0, display: "grid", gap: 6 }}>
        {a.limitations.map((l) => <li key={l}>{l}</li>)}
      </ul>

      <hr className="hairline strong" style={{ marginTop: 24 }} />
      <Title>Server</Title>
      <div className="toggle" style={{ fontSize: 14 }}>
        Live calculation
        <button className="switch" role="switch" aria-checked={liveEnabled} onClick={() => setLiveEnabled(!liveEnabled)} />
      </div>
      <Row label="Backend" value={__BACKEND_TARGET__} />
      <Row label="Status" value={
        connection === "online" ? `Online · model ${health?.model_version ?? "?"}`
          : connection === "offline" ? "Unreachable" : connection === "checking" ? "Checking…" : "Off (saved only)"
      } />
      <button className="link" onClick={checkConnection} style={{ marginTop: 8 }}>Check again</button>
      <p className="caption" style={{ marginTop: 10 }}>
        To use another backend, restart the desktop app with BACKEND_URL set (see desktop/README.md).
      </p>
    </Drawer>
  );
}

function Title({ children, first }: { children: ReactNode; first?: boolean }) {
  return <p style={{ fontSize: 17, fontWeight: 500, margin: first ? "14px 0 6px" : "22px 0 8px" }}>{children}</p>;
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="row" style={{ minHeight: 36, borderBottom: "1px solid var(--hairline)" }}>
      <span className="title" style={{ fontSize: 14 }}>{label}</span>
      <span className="value" style={{ fontSize: 14 }}>{value}</span>
    </div>
  );
}
