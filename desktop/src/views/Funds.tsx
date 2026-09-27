import { useEffect, useRef, useState, type ReactNode } from "react";
import { api, errorMessage } from "../api/client";
import type { ScreenFact } from "../api/chatContext";
import type {
  AccountType, AvailabilityLabel, CatalogSummary, ExclusionReason, FundDetail, FundRecommendation,
  FundShortlistEnvelope, RiskTolerance,
} from "../api/funds";
import { Icon, Stepper } from "../components/ui";
import { asOfLabel, money } from "../data/format";
import { bestInRow, shortName } from "../data/fundView";
import { useStore } from "../store";

const AVAILABILITY: Record<AvailabilityLabel, { text: string; short: string; confirmed: boolean }> = {
  in_supplied_plan_menu: { text: "In your plan menu", short: "In your plan", confirmed: true },
  research_candidate_plan_menu_unconfirmed: { text: "Research candidate · plan menu not confirmed", short: "Not confirmed", confirmed: false },
  discoverable_not_confirmed_purchasable: { text: "Availability not confirmed · check your brokerage", short: "Check brokerage", confirmed: false },
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

const RISK_LABEL: Record<RiskTolerance, string> = { conservative: "Conservative", moderate: "Moderate", growth: "Growth" };

/** How the overall match score is built (the backend's score_weights), in display order. */
const FIT_PARTS: { key: keyof FundRecommendation["score_components"]; label: string }[] = [
  { key: "horizon_fit", label: "Target year near yours" },
  { key: "risk_fit", label: "Stock share near your risk choice" },
  { key: "fee_fit", label: "Low cost" },
  { key: "data_completeness", label: "Verified data complete" },
];

/** Two decimals for expense ratios: 0.0009 → "0.09%". */
const fee = (rate: number) => `${(rate * 100).toFixed(2)}%`;
const pct1 = (rate: number) => `${(Math.round(rate * 1000) / 10).toFixed(1)}%`;
const signed = (rate: number) => `${rate >= 0 ? "+" : "−"}${pct1(Math.abs(rate))}`;
const score100 = (v: number) => Math.round(v * 100);

type Result =
  | { status: "idle" }
  | { status: "loading"; previous?: FundShortlistEnvelope }
  | { status: "loaded"; data: FundShortlistEnvelope }
  | { status: "failed"; message: string };

/**
 * Fund shortlist, laid out like a screener: criteria on top (results update as they change), a
 * side-by-side table of the matches, then one detail card per fund. Every number comes from the
 * reviewed catalog through /v1/funds/shortlist.
 */
export function Funds({ onContext }: { onContext: (facts: ScreenFact[]) => void }) {
  const { profile } = useStore();
  const thisYear = Number(profile.as_of_date.slice(0, 4));
  const defaultYear = thisYear + (profile.retirement_age - profile.age);

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

  // Like a screener: the list updates whenever a criterion changes. Only the latest request counts.
  const menuIDs = account === "401k" && menuKnown ? menu : null;
  const menuKey = menuIDs ? menuIDs.join(",") : "none";
  useEffect(() => {
    const id = ++requestID.current;
    setResult((cur) => ({ status: "loading", previous: cur.status === "loaded" ? cur.data : cur.status === "loading" ? cur.previous : undefined }));
    api.fundShortlist({ account_type: account, retirement_year: year, risk_tolerance: risk, plan_menu_fund_ids: menuIDs })
      .then((data) => { if (id === requestID.current) setResult({ status: "loaded", data }); })
      .catch((error) => { if (id === requestID.current) setResult({ status: "failed", message: errorMessage(error) }); });
  }, [account, year, risk, menuKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const names = new Map(catalog?.funds.map((f) => [f.fund_id, f.name]) ?? []);
  const data = result.status === "loaded" ? result.data : result.status === "loading" ? result.previous : undefined;

  return (
    <div className="funds-page fade-in">
      <section className="glass card screener" aria-label="Search criteria">
        <div className="screener-row">
          <Criterion label="Account">
            <div className="segmented">
              {(["401k", "ira"] as const).map((a) => (
                <button key={a} aria-pressed={account === a} onClick={() => setAccount(a)}>{a === "401k" ? "401(k)" : "IRA"}</button>
              ))}
            </div>
          </Criterion>
          <Criterion label="Risk tolerance" hint="Your choice, not inferred">
            <div className="segmented">
              {(["conservative", "moderate", "growth"] as const).map((r) => (
                <button key={r} aria-pressed={risk === r} onClick={() => setRisk(r)}>{RISK_LABEL[r]}</button>
              ))}
            </div>
          </Criterion>
          <Criterion label="Retirement year" hint={year === defaultYear ? `From your plan (age ${profile.retirement_age})` : `Your plan says ${defaultYear}`}>
            <span className="screener-year">
              <span className="num">{year}</span>
              <Stepper label="retirement year" canDecrement={year > thisYear} canIncrement={year < thisYear + 60}
                onDecrement={() => setYear(year - 1)} onIncrement={() => setYear(year + 1)} />
            </span>
          </Criterion>
          {account === "401k" && (
            <Criterion label="Plan menu" hint={menuKnown ? `${menu.length} ticked` : "Unknown"}>
              <span className="screener-toggle">
                <span className="label">I know my plan's funds</span>
                <button className="switch" role="switch" aria-checked={menuKnown} aria-label="I know my plan's fund menu"
                  onClick={() => setMenuKnown(!menuKnown)} />
              </span>
            </Criterion>
          )}
        </div>
        {account === "401k" && menuKnown && (
          <div className="fund-menu fade-in">
            <p className="caption" style={{ gridColumn: "1 / -1", padding: "2px 8px 4px" }}>Tick the funds your plan offers; only those can be recommended.</p>
            {catalog?.funds.map((f) => (
              <label key={f.fund_id} className="check-row">
                <input type="checkbox" checked={menu.includes(f.fund_id)}
                  onChange={(e) => setMenu(e.target.checked ? [...menu, f.fund_id] : menu.filter((x) => x !== f.fund_id))} />
                <span>{shortName(f.name)}{f.ticker ? ` · ${f.ticker}` : ""}</span>
              </label>
            ))}
            {catalogError && <p className="caption">{catalogError}</p>}
          </div>
        )}
      </section>

      {result.status === "failed" && <div className="banner fade-in"><span>{result.message}</span></div>}
      {!data && result.status !== "failed" && (
        <p className="caption" role="status"><span className="spinner" /> Ranking the reviewed funds…</p>
      )}
      {data && <Results data={data} names={names} loading={result.status === "loading"} menuKnown={account === "401k" && menuKnown} />}

      {catalog && (
        <p className="fine">
          Catalog {catalog.catalog_version}, reviewed by {catalog.reviewed_by} on {asOfLabel(catalog.published_on)}. {catalog.review_note}
        </p>
      )}
    </div>
  );
}

function Criterion({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="criterion">
      <span className="criterion-label">{label}{hint && <span className="criterion-hint"> · {hint}</span>}</span>
      {children}
    </div>
  );
}

// ---------- Results ----------

function Results({ data, names, loading, menuKnown }: {
  data: FundShortlistEnvelope; names: Map<string, string>; loading: boolean; menuKnown: boolean;
}) {
  const { shortlist, details } = data;
  const recs = shortlist.recommendations;
  return (
    <div className={`stack funds-results ${loading ? "is-loading" : ""}`} aria-busy={loading}>
      <div className="results-head">
        <div>
          <h2 className="h-section">
            {recs.length === 0 ? "No fund qualifies" : `${recs.length} fund${recs.length > 1 ? "s" : ""} matched`}
          </h2>
          <p className="subtitle">
            {shortlist.excluded.length} reviewed fund{shortlist.excluded.length === 1 ? "" : "s"} excluded ·
            {" "}{shortlist.plan_menu_status === "confirmed" ? "limited to your plan menu" : menuKnown ? "plan menu applied" : "plan menu unknown, so these are research candidates"}
          </p>
        </div>
        {loading && <span className="caption"><span className="spinner" /> Updating…</span>}
      </div>

      {data.unmatched_plan_menu_ids.length > 0 && (
        <div className="banner"><span>Not in our reviewed catalog: {data.unmatched_plan_menu_ids.join(", ")}.</span></div>
      )}
      {recs.length === 0 && (
        <section className="section">
          <p className="body">None of the reviewed funds passed the checks below. We don't fill gaps with estimates.</p>
        </section>
      )}
      {recs.length > 0 && <SideBySide recs={recs} details={details} />}
      {recs.map((rec, i) => <FundCard key={rec.fund_id} rank={i + 1} rec={rec} detail={details[rec.fund_id]} defaultOpen={i === 0}
        weights={shortlist.score_weights} />)}

      {shortlist.excluded.length > 0 && (
        <section className="section">
          <h2 className="h-card">Not recommended</h2>
          <p className="subtitle">Reviewed funds that failed a check</p>
          <table className="table compact" style={{ marginTop: 12 }}>
            <tbody>
              {shortlist.excluded.map((e) => (
                <tr key={e.fund_id}><td>{shortName(names.get(e.fund_id) ?? e.fund_id)}</td><td className="muted">{EXCLUDED[e.reason_code]}</td></tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
      <p className="fine">{shortlist.hypothetical_disclosure}</p>
    </div>
  );
}

/** Top matches in one table; the best value in each comparable row is marked. */
function SideBySide({ recs, details }: { recs: FundRecommendation[]; details: Record<string, FundDetail> }) {
  const periods = [...new Set(recs.flatMap((r) => r.historical_returns.map((h) => h.period_years)))].sort((a, b) => a - b);
  type Row = { label: ReactNode; cell: (r: FundRecommendation) => ReactNode; value?: (r: FundRecommendation) => number | undefined; lowest?: boolean };
  const baseYears = recs[0].hypothetical_scenarios.find((s) => s.label === "base")?.years;
  const rows: Row[] = [
    { label: "Match score", cell: (r) => <>{score100(r.score)}<span className="caption"> /100</span></>, value: (r) => score100(r.score) },
    { label: "Target year", cell: (r) => r.target_year },
    { label: "Expense ratio", cell: (r) => <>{fee(r.expense_ratio)}{details[r.fund_id]?.fees.waiver_active && <span className="caption"> after waiver</span>}</>, value: (r) => r.expense_ratio, lowest: true },
    { label: "Stocks / bonds", cell: (r) => `${pct1(r.equity_weight)} / ${pct1(r.bond_weight)}` },
    { label: "Risk band", cell: (r) => <>{r.risk_band}<span className="caption"> /5</span></> },
    ...periods.map((y): Row => ({
      label: `${y}-year return`,
      cell: (r) => { const h = r.historical_returns.find((x) => x.period_years === y); return h ? signed(h.annualized_return_rate) : <span className="caption">No record</span>; },
      value: (r) => r.historical_returns.find((x) => x.period_years === y)?.annualized_return_rate,
    })),
    ...(baseYears ? [{
      label: <>Base case in {baseYears} yrs</>,
      cell: (r: FundRecommendation) => money(r.hypothetical_scenarios.find((s) => s.label === "base")?.hypothetical_end_cents ?? 0),
      value: (r: FundRecommendation) => r.hypothetical_scenarios.find((s) => s.label === "base")?.hypothetical_end_cents,
    }] : []),
    { label: "Availability", cell: (r) => <span className={AVAILABILITY[r.availability_label].confirmed ? "avail ok" : "avail"}>{AVAILABILITY[r.availability_label].short}</span> },
  ];
  return (
    <section className="section" aria-labelledby="side-title">
      <h2 id="side-title" className="h-card">Side by side</h2>
      <p className="subtitle">Ranked by match score · <span className="best-mark">●</span> best in row</p>
      <div className="table-scroll">
        <table className="table compare-table">
          <thead>
            <tr>
              <th scope="col"><span className="sr-only">Measure</span></th>
              {recs.map((r, i) => (
                <th key={r.fund_id} scope="col">
                  <span className="compare-rank">#{i + 1}</span>
                  <span className="compare-name">{shortName(r.name)}</span>
                  <span className="caption">{details[r.fund_id]?.ticker ?? details[r.fund_id]?.class_name}</span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, i) => {
              const top = row.value ? bestInRow(recs.map(row.value), row.lowest) : undefined;
              return (
                <tr key={i}>
                  <th scope="row">{row.label}</th>
                  {recs.map((r) => (
                    <td key={r.fund_id} className={top !== undefined && row.value?.(r) === top ? "best" : ""}>{row.cell(r)}</td>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function FundCard({ rank, rec, detail, defaultOpen, weights }: {
  rank: number; rec: FundRecommendation; detail: FundDetail; defaultOpen: boolean; weights: Record<string, number>;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const availability = AVAILABILITY[rec.availability_label];
  const base = rec.hypothetical_scenarios.find((s) => s.label === "base");
  const bodyID = `fund-${rec.fund_id}`;
  return (
    <section className={`section fund-card ${open ? "open" : ""}`}>
      <button className="fund-card-head" aria-expanded={open} aria-controls={bodyID} onClick={() => setOpen(!open)}>
        <span className="step-num">{rank}</span>
        <span className="fund-card-title">
          <span className="h-card">{rec.name}</span>
          <span className="caption">{detail.issuer} · {detail.class_name}{detail.ticker ? ` · ${detail.ticker}` : ""} · {fee(rec.expense_ratio)} · {rec.target_year}</span>
        </span>
        <span className="fund-score"><b className="num">{score100(rec.score)}</b><span className="caption">match</span></span>
        <span className="disclosure-chevron"><Icon name="chevron" size={14} /></span>
      </button>

      {open && (
        <div id={bodyID} className="fund-card-body fade-in">
          <p className={`avail-line ${availability.confirmed ? "ok" : ""}`}><Icon name={availability.confirmed ? "check" : "why"} size={14} /> {availability.text}</p>
          <div className="fund-grid">
            <FundBlock title="Costs">
              <Fact label={`Expense ratio${detail.fees.waiver_active ? " (after waiver)" : ""}`} value={fee(rec.expense_ratio)} />
              {detail.fees.waiver_active && <>
                <Fact label="Before waiver" value={fee(detail.fees.gross_expense_ratio)} />
                <Fact label={`Waiver, until ${asOfLabel(detail.fees.waiver_ends!)}`} value={`−${fee(detail.fees.fee_waiver)}`} />
              </>}
              <Fact label="Underlying-fund costs (included)" value={fee(detail.fees.acquired_fund_fees)} />
              <p className="caption">On {money(10_000_00)} that's about {money(Math.round(10_000_00 * rec.expense_ratio))} a year.</p>
            </FundBlock>

            <FundBlock title="What it holds" note={`As of ${asOfLabel(rec.facts_as_of_date)}, issuer's shareholder report`}>
              <MixBar equity={rec.equity_weight} bond={rec.bond_weight} other={rec.other_weight} />
              <div className="holdings">
                {detail.allocation.reported_categories.map((c) => (
                  <Fact key={c.label} label={c.label} value={`${c.percent_of_net_assets.toFixed(1)}%`} />
                ))}
              </div>
            </FundBlock>

            <FundBlock title="Why it matched" note={`Overall ${score100(rec.score)}/100`}>
              {FIT_PARTS.map((p) => (
                <FitRow key={p.key} label={weights[p.key] !== undefined ? `${p.label} · ${Math.round(weights[p.key] * 100)}%` : p.label}
                  value={rec.score_components[p.key]} />
              ))}
              <p className="caption">Each part is scored 0–100; the percent is its weight in the overall score.</p>
            </FundBlock>

            <FundBlock title="Past performance" note={rec.historical_returns[0] ? `Average annual total return to ${asOfLabel(rec.historical_returns[0].as_of_date)}` : undefined}>
              {rec.historical_returns.length === 0 && <p className="caption">Not available.</p>}
              {rec.historical_returns.map((h) => (
                <Fact key={h.period_years} label={`${h.period_years} year${h.period_years > 1 ? "s" : ""}`} value={signed(h.annualized_return_rate)} />
              ))}
              <p className="caption">Past results don't predict future returns.</p>
            </FundBlock>

            <FundBlock title="Hypothetical growth" note={base ? `${money(base.hypothetical_start_cents)} over ${base.years} years, today's mix held` : undefined}>
              {rec.hypothetical_scenarios.map((s) => (
                <Fact key={s.label} label={<span style={{ textTransform: "capitalize" }}>{s.label} <span className="caption">{signed(s.annual_net_return_rate)}/yr</span></span>}
                  value={money(s.hypothetical_end_cents)} />
              ))}
              <p className="caption">An illustration, not a forecast.</p>
            </FundBlock>

            <FundBlock title="Glide path">
              <p className="body small">{detail.glide_path}</p>
              {detail.allocation.mapping_note && <p className="caption">{detail.allocation.mapping_note}</p>}
            </FundBlock>
          </div>

          <div className="fund-sources">
            <span className="caption">Sources</span>
            <a className="link" href={detail.prospectus.url} target="_blank" rel="noreferrer"><Icon name="link" size={13} /> Prospectus ({asOfLabel(detail.prospectus.filed_date)})</a>
            <a className="link" href={detail.fees.evidence_url} target="_blank" rel="noreferrer"><Icon name="link" size={13} /> Fee table</a>
            <a className="link" href={detail.allocation.evidence_url} target="_blank" rel="noreferrer"><Icon name="link" size={13} /> Holdings ({asOfLabel(detail.allocation.as_of_date)})</a>
          </div>
          {(detail.caveats.length > 0 || detail.fees.waiver_active) && (
            <ul className="fund-caveats">
              {detail.fees.waiver_active && <li className="caption">{detail.fees.waiver_terms}</li>}
              {detail.caveats.map((c) => <li key={c} className="caption">{c}</li>)}
            </ul>
          )}
        </div>
      )}
    </section>
  );
}

function FundBlock({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return (
    <div className="fund-block">
      <p className="fund-block-title">{title}</p>
      {note && <p className="caption fund-block-note">{note}</p>}
      <div className="fund-block-body">{children}</div>
    </div>
  );
}

function Fact({ label, value }: { label: ReactNode; value: ReactNode }) {
  return (
    <div className="fact">
      <span className="fact-label">{label}</span>
      <span className="fact-value num">{value}</span>
    </div>
  );
}

function MixBar({ equity, bond, other }: { equity: number; bond: number; other: number }) {
  const parts = [
    { key: "Stocks", value: equity, fill: "var(--accent)" },
    { key: "Bonds", value: bond, fill: "var(--blue-mid)" },
    { key: "Other", value: other, fill: "var(--quiet)" },
  ].filter((p) => p.value > 0);
  return (
    <>
      <div className="band" style={{ height: 10 }} role="img" aria-label={parts.map((p) => `${p.key} ${pct1(p.value)}`).join(", ")}>
        {parts.map((p) => (
          <div key={p.key} className="band-seg" style={{ background: p.fill, flexGrow: p.value, flexBasis: 0, borderRadius: 5 }} />
        ))}
      </div>
      <div className="mix-legend">
        {parts.map((p) => (
          <span key={p.key}><i style={{ background: p.fill }} />{p.key} <b className="num">{pct1(p.value)}</b></span>
        ))}
      </div>
    </>
  );
}

function FitRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="fit-row">
      <span className="fact-label">{label}</span>
      <span className="fit-track"><i style={{ width: `${score100(value)}%` }} /></span>
      <span className="num fact-value" style={{ width: 30, textAlign: "right" }}>{score100(value)}</span>
    </div>
  );
}
