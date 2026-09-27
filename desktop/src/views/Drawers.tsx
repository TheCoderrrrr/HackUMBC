import type { ReactNode } from "react";
import { Drawer, Icon } from "../components/ui";
import { debtName, explanationSteps, PRIORITY_LABEL, type Display } from "../data/display";
import { asOfLabel, money, moneyExact, months, percent } from "../data/format";
import { usesBundle } from "../data/saved";
import { useStore, type PlanSection } from "../store";
import { Term } from "../components/Term";
import { STYLE_INFO } from "../data/styles";
import { when } from "./Plan";

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
  if (drawer && typeof drawer === "object") return <SectionWhy section={drawer.why} display={display} onClose={close} />;
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
        To use another backend, restart the desktop app with BACKEND_URL set (see docs/DESKTOP.md).
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

// ---------- "Why this matters", one per plan section ----------

type WhyContent = { title: string; what: ReactNode; effect: ReactNode; change: ReactNode; action?: { label: string; run: () => void } };

/**
 * Each section's own explanation: what it is, how it shapes the retirement fund (engine numbers,
 * your plan next to current habits), and what could change the outcome.
 */
function SectionWhy({ section, display, onClose }: { section: PlanSection; display: Display; onClose: () => void }) {
  const { setDrawer, setTab, style } = useStore();
  const { profile, evaluation } = display;
  const { adaptive, current } = evaluation.projections;
  const a = evaluation.assumptions;
  const asOf = profile.as_of_date;
  const age = profile.retirement_age;
  const planAt = cents(adaptive.retirement_balance_nominal_cents);
  const habitsAt = cents(current.retirement_balance_nominal_cents);
  const fullMatch = evaluation.financial_state.employee_rate_for_full_match;

  const content: Record<PlanSection, WhyContent> = {
    month: {
      title: "Why the order of your money matters",
      what: <>After living costs and minimum payments, ARM splits what's left between retirement saving, extra debt
        payments and cash savings, in the order set by your <Term id="plan-style">plan style</Term>.</>,
      effect: <>Money that clears expensive debt or builds a cushion now frees more for retirement later. With this
        plan you're projected to have <b>{planAt}</b> at {age}, compared with <b>{habitsAt}</b> if you keep your current habits.</>,
      change: <>A raise, a new bill or a paid-off debt changes what's left each month, and the split changes with it.</>,
      action: { label: "See the full reasoning", run: () => setDrawer("explanation") },
    },
    saving: {
      title: "Why saving now matters",
      what: <>What you contribute from each paycheck, plus what your <Term id="employer-match">employer match</Term> adds.</>,
      effect: <>Every dollar saved now has {display.yearsToRetirement} years of <Term id="compound-growth">compound growth</Term> ahead.
        You add <b>{moneyExact(display.employeeCents)}</b> a month
        {display.employerCents ? <> and your employer adds <b>{moneyExact(display.employerCents)}</b></> : null}.
        That's what builds toward <b>{planAt}</b> at {age}.</>,
      change: <>{fullMatch !== null && <>Contributing less than {percent(fullMatch)} leaves employer money unclaimed. </>}
        Salary growth ({percent(a.annual_salary_growth)} a year assumed), market returns and contribution limits all change the result.</>,
      action: { label: "Try a different rate in Explore", run: () => { setTab("explore"); onClose(); } },
    },
    debt: {
      title: "Why paying down debt matters",
      what: <>Your debts and what the plan pays on them each month. <Term id="high-interest-debt">High-interest debt</Term> gets
        extra payments first.</>,
      effect: <>Interest is money that can't grow for retirement. With this plan, high-interest debt is cleared
        by <b>{when(adaptive.debt_free_month, asOf, "now")}</b> and you pay <b>{cents(adaptive.cumulative_debt_interest_cents)}</b> in
        interest. On current habits: <b>{when(current.debt_free_month, asOf, "now")}</b> and <b>{cents(current.cumulative_debt_interest_cents)}</b>.
        Once it's gone, that payment can go to savings.</>,
      change: <>New borrowing, a missed payment or a rate increase pushes the payoff date later. The model assumes
        your <Term id="apr">APR</Term> and minimums stay fixed.</>,
    },
    emergency: {
      title: "Why an emergency fund matters",
      what: <>Cash you can reach quickly for surprises, built as a <Term id="cushion">one-month cushion</Term> first,
        then a full {display.fullMonths}-month fund.</>,
      effect: <>Without it, a surprise bill often lands on a credit card or comes out of your retirement account, which
        can mean taxes, penalties and years of lost growth. Your plan reaches the full fund
        by <b>{when(adaptive.full_reserve_month, asOf)}</b> (current habits: <b>{when(current.full_reserve_month, asOf)}</b>).</>,
      change: <>Living costs rising faster than the assumed {percent(a.annual_living_cost_growth)} a year raise the target.
        Spending the fund on a real emergency is what it's for; the plan rebuilds it afterwards.</>,
    },
    fund: {
      title: "Why your fund's mix matters",
      what: <>Your <Term id="target-date-fund">target-date fund</Term> holds about {percent(display.equityWeight)} stocks
        today and follows a <Term id="glide-path">glide path</Term> toward bonds.</>,
      effect: <>The projection assumes stocks earn {percent(a.annual_equity_return)} and bonds {percent(a.annual_bond_return)} a
        year after fees. More stocks early means more growth; more bonds later protects what you've built.
        ARM doesn't change this mix; it changes how much you put in.</>,
      change: <>Real returns rise and fall from year to year, so actual balances will differ from the steady projection.
        A fund with higher fees or a different mix would change the result.</>,
      action: { label: "Compare target-date funds", run: () => { setTab("funds"); onClose(); } },
    },
    style: {
      title: "Why your plan style matters",
      what: <>You're on <b>{STYLE_INFO[style].label}</b>. A <Term id="plan-style">plan style</Term> decides what your extra
        money pays for first once the basics are covered.</>,
      effect: <>It changes when debt is cleared and when your emergency fund is full, and so how soon more money can
        go to retirement. For some people all three styles end up the same.</>,
      change: <>You can switch anytime. The live plan may choose a different order within the same rules when that
        fits your numbers better, and it tells you when it does.</>,
    },
  };

  const c = content[section];
  return (
    <Drawer title={c.title} onClose={onClose}
      footer={c.action ? <button className="btn-primary full" onClick={c.action.run}>{c.action.label}</button>
        : <button className="btn-primary full" onClick={onClose}>Got it</button>}>
      <WhyBlock n={1} title="What it is">{c.what}</WhyBlock>
      <WhyBlock n={2} title="How it shapes your retirement fund">{c.effect}</WhyBlock>
      <WhyBlock n={3} title="What could change it">{c.change}</WhyBlock>
      <p className="caption" style={{ marginTop: 20 }}>
        Numbers from your {display.origin.toLowerCase()} result, as of {asOfLabel(asOf)}. Illustrative, not a guarantee.
      </p>
    </Drawer>
  );
}

const cents = (v: number | null) => (v === null ? "—" : money(v));

function WhyBlock({ n, title, children }: { n: number; title: string; children: ReactNode }) {
  return (
    <div className="why-block">
      <span className="step-num">{n}</span>
      <div>
        <p className="why-block-title">{title}</p>
        <p className="body why-block-text">{children}</p>
      </div>
    </div>
  );
}
