import { useEffect, useRef, useState } from "react";
import { api, errorMessage } from "../api/client";
import type { ScreenFact } from "../api/chatContext";
import type {
  AccountType, AvailabilityLabel, CatalogSummary, ExclusionReason, FundDetail, FundRecommendation,
  FundShortlistEnvelope, RiskTolerance,
} from "../api/funds";
import { Icon, SectionHeader, Stepper } from "../components/ui";
import { asOfLabel, money } from "../data/format";
import { useStore } from "../store";

const AVAILABILITY: Record<AvailabilityLabel, { text: string; tone: "chip" | "chip muted" }> = {
  in_supplied_plan_menu: { text: "In your plan menu", tone: "chip" },
  research_candidate_plan_menu_unconfirmed: { text: "Research candidate · plan menu not confirmed", tone: "chip muted" },
  discoverable_not_confirmed_purchasable: { text: "Availability not confirmed · check your brokerage", tone: "chip muted" },
};

const EXCLUDED: Record<ExclusionReason, string> = {
  NOT_IN_PLAN_MENU: "Not in your plan menu",
  UNAVAILABLE: "Marked unavailable",
  INCOMPLETE_FACTS: "Missing verified fee or allocation data",
  STALE_FACTS: "Verified data is too old to rank",
  NOT_TARGET_DATE: "Not a target-date fund",
  NON_USD: "Not priced in US dollars",
  POOR_HORIZON_FIT: "Target year too far from yours",
  POOR_RISK_FIT: "Stock mix too far from your risk choice",
};

const RISK_LABEL: Record<RiskTolerance, string> = {
  conservative: "Conservative",
  moderate: "Moderate",
  growth: "Growth",
};

/** Two decimals for expense ratios: 0.0009 → "0.09%". */
const fee = (rate: number) => `${(rate * 100).toFixed(2)}%`;
const pct1 = (rate: number) => `${(Math.round(rate * 1000) / 10).toFixed(1)}%`;
const signed = (rate: number) => `${rate >= 0 ? "+" : "−"}${pct1(Math.abs(rate))}`;

type Result =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "loaded"; data: FundShortlistEnvelope }
  | { status: "failed"; message: string };

export function Funds({ onContext }: { onContext: (facts: ScreenFact[]) => void }) {
  const { profile } = useStore();
  const defaultYear = Number(profile.as_of_date.slice(0, 4)) + (profile.retirement_age - profile.age);
  const thisYear = Number(profile.as_of_date.slice(0, 4));

  const [account, setAccount] = useState<AccountType>("401k");
  const [risk, setRisk] = useState<RiskTolerance>("moderate");
  const [year, setYear] = useState(defaultYear);
  const [menuKnown, setMenuKnown] = useState(false);
  const [menu, setMenu] = useState<string[]>([]);
  const [catalog, setCatalog] = useState<CatalogSummary | null>(null);
  const [catalogError, setCatalogError] = useState<string | null>(null);
  const [result, setResult] = useState<Result>({ status: "idle" });
  const requestID = useRef(0);

  useEffect(() => () => onContext([]), [onContext]);

  useEffect(() => {
    const facts: ScreenFact[] = [
      { label: "account_type", value: account },
      { label: "selected_risk_tolerance", value: risk },
      { label: "selected_retirement_year", value: String(year) },
      { label: "plan_menu_known", value: String(menuKnown) },
      { label: "ranking_method", value: "horizon fit, stock allocation risk fit, fund fees, verified data completeness" },
      { label: "risk_scale", value: "1 to 5, based on current stock weight, not volatility" },
    ];
    if (catalog) facts.push({ label: "catalog_published_on", value: catalog.published_on });
    if (result.status === "loaded") {
      facts.push({ label: "shortlist_count", value: String(result.data.shortlist.recommendations.length) });
      facts.push({ label: "plan_menu_status", value: result.data.shortlist.plan_menu_status });
      result.data.shortlist.recommendations.slice(0, 3).forEach((fund, index) => {
        const label = `fund_${index + 1}`;
        const base = fund.hypothetical_scenarios.find((scenario) => scenario.label === "base");
        const history = fund.historical_returns[0];
        facts.push(
          { label: `${label}_name`, value: fund.name.slice(0, 120) },
          { label: `${label}_target_year`, value: String(fund.target_year) },
          { label: `${label}_expense_ratio`, value: fee(fund.expense_ratio) },
          { label: `${label}_stock_mix`, value: pct1(fund.equity_weight) },
          { label: `${label}_risk_band_out_of_five`, value: String(fund.risk_band) },
          { label: `${label}_availability`, value: fund.availability_label },
          { label: `${label}_facts_as_of`, value: fund.facts_as_of_date },
          { label: `${label}_reason_codes`, value: fund.reason_codes.slice(0, 3).join(", ").slice(0, 120) },
        );
        if (base) facts.push({ label: `${label}_hypothetical_base_annual_return`, value: pct1(base.annual_net_return_rate) });
        if (history) facts.push({ label: `${label}_historical_return`, value: `${pct1(history.annualized_return_rate)} annualized over ${history.period_years} years as of ${history.as_of_date}` });
      });
    }
    onContext(facts);
  }, [account, risk, year, menuKnown, catalog, result, onContext]);

  useEffect(() => setYear(defaultYear), [defaultYear]);

  useEffect(() => {
    const controller = new AbortController();
    api.fundCatalog(controller.signal)
      .then((c) => { setCatalog(c); setCatalogError(null); })
      .catch((e) => { if (!controller.signal.aborted) setCatalogError(errorMessage(e)); });
    return () => controller.abort();
  }, []);

  const search = async () => {
    const id = ++requestID.current;
    setResult({ status: "loading" });
    try {
      const data = await api.fundShortlist({
        account_type: account,
        retirement_year: year,
        risk_tolerance: risk,
        plan_menu_fund_ids: account === "401k" && menuKnown ? menu : null,
      });
      if (id === requestID.current) setResult({ status: "loaded", data });
    } catch (error) {
      if (id === requestID.current) setResult({ status: "failed", message: errorMessage(error) });
    }
  };

  const names = new Map(catalog?.funds.map((f) => [f.fund_id, f.name]) ?? []);

  return (
    <div className="grid funds fade-in">
      <div className="stack" style={{ position: "sticky", top: 24 }}>
        <section className="glass card">
          <h2 className="h-section" style={{ marginBottom: 18 }}>Find a target-date fund</h2>

          <p className="strong" style={{ fontSize: 15, marginBottom: 10 }}>Account</p>
          <div className="segmented">
            {(["401k", "ira"] as const).map((a) => (
              <button key={a} aria-pressed={account === a} onClick={() => setAccount(a)}>{a === "401k" ? "401(k)" : "IRA"}</button>
            ))}
          </div>

          <p className="strong" style={{ fontSize: 15, margin: "20px 0 10px" }}>Risk tolerance</p>
          <div className="segmented">
            {(["conservative", "moderate", "growth"] as const).map((r) => (
              <button key={r} aria-pressed={risk === r} onClick={() => setRisk(r)}>{RISK_LABEL[r]}</button>
            ))}
          </div>
          <p className="caption" style={{ marginTop: 8 }}>
            You choose this. It is not inferred from age, income, or debt.
          </p>

          <div className="row" style={{ marginTop: 14 }}>
            <span className="strong" style={{ fontSize: 15 }}>Retirement year</span>
            <span style={{ display: "flex", alignItems: "center", gap: 14 }}>
              <span className="num" style={{ fontSize: 18, fontWeight: 500 }}>{year}</span>
              <Stepper label="retirement year" canDecrement={year > thisYear} canIncrement={year < thisYear + 60}
                onDecrement={() => setYear(year - 1)} onIncrement={() => setYear(year + 1)} />
            </span>
          </div>

          {account === "401k" && (
            <div className="fade-in" style={{ marginTop: 16 }}>
              <div className="toggle" style={{ justifyContent: "space-between", display: "flex", alignItems: "center" }}>
                <span className="strong" style={{ fontSize: 15 }}>I know my plan's fund menu</span>
                <button className="switch" role="switch" aria-checked={menuKnown} aria-label="I know my plan's fund menu"
                  onClick={() => setMenuKnown(!menuKnown)} />
              </div>
              {menuKnown && (
                <div className="fund-menu fade-in">
                  {catalog?.funds.map((f) => (
                    <label key={f.fund_id} className="check-row">
                      <input type="checkbox" checked={menu.includes(f.fund_id)}
                        onChange={(e) => setMenu(e.target.checked ? [...menu, f.fund_id] : menu.filter((x) => x !== f.fund_id))} />
                      <span>{f.name}{f.ticker ? ` (${f.ticker})` : ""}</span>
                    </label>
                  ))}
                  {catalogError && <p className="caption">{catalogError}</p>}
                </div>
              )}
              <p className="caption" style={{ marginTop: 8 }}>
                {menuKnown
                  ? "Only funds you tick can be recommended."
                  : "Without your menu, results are research candidates your plan may not offer."}
              </p>
            </div>
          )}

          <button className="btn-primary full" style={{ marginTop: 22 }} onClick={search} disabled={result.status === "loading"}>
            {result.status === "loading" ? <span className="spinner" /> : <Icon name="funds" />} Show shortlist
          </button>
        </section>

        {catalog && (
          <p className="fine" style={{ padding: "0 6px" }}>
            Catalog {catalog.catalog_version}, reviewed by {catalog.reviewed_by} on {asOfLabel(catalog.published_on)}.
            {" "}{catalog.review_note}
          </p>
        )}
      </div>

      <div className="stack">
        {result.status === "idle" && (
          <section className="section">
            <p className="h-card">A short, sourced list</p>
            <p className="body" style={{ marginTop: 8 }}>
              Up to three target-date funds from a small catalog verified against SEC filings. Every number shows its
              source and date. This is not investment advice.
            </p>
          </section>
        )}
        {result.status === "failed" && (
          <div className="banner fade-in"><span>{result.message}</span></div>
        )}
        {result.status === "loaded" && <Results data={result.data} names={names} />}
      </div>
    </div>
  );
}

function Results({ data, names }: { data: FundShortlistEnvelope; names: Map<string, string> }) {
  const { shortlist, details } = data;
  return (
    <>
      {data.unmatched_plan_menu_ids.length > 0 && (
        <div className="banner"><span>Not in our reviewed catalog: {data.unmatched_plan_menu_ids.join(", ")}.</span></div>
      )}
      {shortlist.recommendations.length === 0 && (
        <section className="section">
          <p className="h-card">No fund qualifies</p>
          <p className="body" style={{ marginTop: 8 }}>None of the reviewed funds passed the checks below. We don't fill gaps with estimates.</p>
        </section>
      )}
      {shortlist.recommendations.map((rec, i) => (
        <FundCard key={rec.fund_id} rank={i + 1} rec={rec} detail={details[rec.fund_id]} />
      ))}
      {shortlist.excluded.length > 0 && (
        <section className="section">
          <SectionHeader title="Not recommended" subtitle="Reviewed funds that did not pass a check" />
          {shortlist.excluded.map((e) => (
            <div className="row" key={e.fund_id}>
              <span className="title" style={{ fontSize: 14 }}>{names.get(e.fund_id) ?? e.fund_id}</span>
              <span className="caption">{EXCLUDED[e.reason_code]}</span>
            </div>
          ))}
        </section>
      )}
      <p className="fine" style={{ padding: "0 6px" }}>{shortlist.hypothetical_disclosure}</p>
    </>
  );
}

function FundCard({ rank, rec, detail }: { rank: number; rec: FundRecommendation; detail: FundDetail }) {
  const availability = AVAILABILITY[rec.availability_label];
  const base = rec.hypothetical_scenarios.find((s) => s.label === "base");
  return (
    <section className="section fade-in">
      <div style={{ display: "flex", alignItems: "flex-start", gap: 14, marginBottom: 18 }}>
        <span className="step-num">{rank}</span>
        <div style={{ flex: 1 }}>
          <h2 className="h-section">{rec.name}</h2>
          <p className="caption" style={{ marginTop: 3 }}>
            {detail.issuer} · {detail.class_name}{detail.ticker ? ` · ${detail.ticker}` : ""} · share class {rec.share_class_id}
          </p>
        </div>
        <span className={availability.tone}>{availability.text}</span>
      </div>

      <div className="fund-figures">
        <div>
          <div className="figure" style={{ fontSize: 30 }}>{fee(rec.expense_ratio)}</div>
          <div className="caption">Expense ratio{detail.fees.waiver_active ? " after waiver" : ""}</div>
        </div>
        <div>
          <div className="figure" style={{ fontSize: 30 }}>{rec.target_year}</div>
          <div className="caption">Target year</div>
        </div>
        <div>
          <div className="figure" style={{ fontSize: 30 }}>{rec.risk_band}<span className="caption" style={{ fontSize: 15 }}> / 5</span></div>
          <div className="caption">Risk band (stock share only)</div>
        </div>
      </div>
      {detail.fees.waiver_active && (
        <p className="caption" style={{ marginTop: 10 }}>
          {fee(detail.fees.gross_expense_ratio)} before a {fee(detail.fees.fee_waiver)} waiver that runs through{" "}
          {asOfLabel(detail.fees.waiver_ends!)}. Includes {fee(detail.fees.acquired_fund_fees)} of underlying-fund costs. {detail.fees.waiver_terms}
        </p>
      )}

      <p className="strong" style={{ fontSize: 15, margin: "22px 0 10px" }}>Current mix</p>
      <MixBar equity={rec.equity_weight} bond={rec.bond_weight} other={rec.other_weight} />
      <p className="caption" style={{ marginTop: 8 }}>
        As of {asOfLabel(rec.facts_as_of_date)} from the issuer's shareholder report. {detail.allocation.mapping_note}
      </p>
      <p className="caption" style={{ marginTop: 4 }}>{detail.glide_path}</p>

      <p className="strong" style={{ fontSize: 15, margin: "22px 0 8px" }}>Why it matched</p>
      <FitRow label="Target year near yours" value={rec.score_components.horizon_fit} />
      <FitRow label="Stock share near your risk choice" value={rec.score_components.risk_fit} />
      <FitRow label="Low cost" value={rec.score_components.fee_fit} />

      <div className="fund-split">
        <div>
          <p className="strong" style={{ fontSize: 15, marginBottom: 4 }}>Past performance</p>
          <p className="caption" style={{ marginBottom: 8 }}>
            {rec.historical_returns.length
              ? `Average annual total returns to ${asOfLabel(rec.historical_returns[0].as_of_date)}. Past results don't predict future returns.`
              : "Not available."}
          </p>
          {rec.historical_returns.map((h) => (
            <div className="row" key={h.period_years} style={{ minHeight: 30 }}>
              <span className="title" style={{ fontSize: 14 }}>{h.period_years} year{h.period_years > 1 ? "s" : ""}</span>
              <span className="value" style={{ fontSize: 15 }}>{signed(h.annualized_return_rate)}</span>
            </div>
          ))}
        </div>
        <div>
          <p className="strong" style={{ fontSize: 15, marginBottom: 4 }}>Hypothetical illustration</p>
          <p className="caption" style={{ marginBottom: 8 }}>
            {money(base?.hypothetical_start_cents ?? 0)} over {base?.years} years if today's mix never changed. Not a forecast.
          </p>
          {rec.hypothetical_scenarios.map((s) => (
            <div className="row" key={s.label} style={{ minHeight: 30 }}>
              <span className="title" style={{ fontSize: 14, textTransform: "capitalize" }}>
                {s.label} <span className="caption">({signed(s.annual_net_return_rate)}/yr)</span>
              </span>
              <span className="value" style={{ fontSize: 15 }}>{money(s.hypothetical_end_cents)}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="fund-sources">
        <a className="link" href={detail.prospectus.url} target="_blank" rel="noreferrer">
          <Icon name="link" size={13} /> Prospectus, filed {asOfLabel(detail.prospectus.filed_date)}
        </a>
        <a className="link" href={detail.fees.evidence_url} target="_blank" rel="noreferrer">
          <Icon name="link" size={13} /> Fee table
        </a>
        <a className="link" href={detail.allocation.evidence_url} target="_blank" rel="noreferrer">
          <Icon name="link" size={13} /> Holdings, {asOfLabel(detail.allocation.as_of_date)}
        </a>
      </div>
      {detail.caveats.length > 0 && (
        <ul className="fund-caveats">
          {detail.caveats.map((c) => <li key={c} className="caption">{c}</li>)}
        </ul>
      )}
    </section>
  );
}

function MixBar({ equity, bond, other }: { equity: number; bond: number; other: number }) {
  const parts = [
    { key: "Stocks", value: equity, fill: "var(--accent)" },
    { key: "Bonds", value: bond, fill: "var(--bonds)" },
    { key: "Other", value: other, fill: "var(--quiet)" },
  ].filter((p) => p.value > 0);
  return (
    <>
      <div className="band" style={{ height: 12 }} role="img" aria-label={parts.map((p) => `${p.key} ${pct1(p.value)}`).join(", ")}>
        {parts.map((p) => (
          <div key={p.key} className="band-seg" style={{ background: p.fill, flexGrow: p.value, flexBasis: 0, borderRadius: 6 }} />
        ))}
      </div>
      <div style={{ display: "flex", gap: 18, marginTop: 8 }}>
        {parts.map((p) => (
          <span key={p.key} className="label" style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <i style={{ width: 7, height: 7, borderRadius: "50%", background: p.fill, display: "inline-block" }} />
            {p.key} <span className="num strong">{pct1(p.value)}</span>
          </span>
        ))}
      </div>
    </>
  );
}

function FitRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="fit-row">
      <span className="label">{label}</span>
      <span className="fit-track"><i style={{ width: `${Math.round(value * 100)}%` }} /></span>
      <span className="num caption" style={{ width: 34, textAlign: "right" }}>{Math.round(value * 100)}</span>
    </div>
  );
}
