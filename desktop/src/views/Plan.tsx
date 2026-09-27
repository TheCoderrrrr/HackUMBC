import {
  AllocationRing, BAND, CASH_ACCENT, Figure, Icon, MonthMeter, SectionHeader, SegmentedBand, ShareBand, Stat,
} from "../components/ui";
import { DISCLOSURE, type Display, type DisplayDebt } from "../data/display";
import { money, moneyExact, monthLabel, months, percent } from "../data/format";
import { useStore } from "../store";

const TILE_TITLE = {
  retirement: "Retirement take-home cost",
  debt: "Extra debt payment",
  emergency: "Emergency savings",
  remaining: "Remaining cash",
} as const;

export function Plan({ display }: { display: Display }) {
  const { setDrawer } = useStore();
  const why = () => setDrawer("explanation");
  const { profile } = display;
  const total = display.employeeCents + (display.employerCents ?? 0);

  return (
    <div className="grid plan fade-in" key={profile.id}>
      <section className="section">
        <SectionHeader title="Retirement contributions" onWhy={why} />
        <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 24 }}>
          <Figure>{percent(display.rate)}</Figure>
          <span className="label" style={{ fontSize: 15 }}>of salary</span>
          <span style={{ marginLeft: "auto" }}>
            {display.matchCaptured && <span className="chip"><Icon name="seal" size={12} /> Full match</span>}
          </span>
        </div>
        <SegmentedBand segments={[
          { label: "You", value: money(display.employeeCents), weight: display.employeeCents, fill: BAND.retirement },
          ...(display.employerCents
            ? [{ label: "Employer", value: `+${money(display.employerCents)}`, weight: display.employerCents, fill: BAND.employer }]
            : []),
        ]} />
        <div style={{ display: "flex", gap: 16, marginTop: 18 }}>
          <Stat value={money(total)} unit="/ mo" caption="Into retirement" />
          <Stat value={moneyExact(display.takeHomeCostCents)} caption="Your take-home cost" align="right" />
        </div>
        {display.rate !== display.currentRate && (
          <p className="caption" style={{ marginTop: 16 }}>
            Changed from {percent(display.currentRate)} today. The plan revisits this as priorities are met.
          </p>
        )}
      </section>

      <section className="section">
        <SectionHeader title="Monthly cash priorities" onWhy={why} />
        <ShareBand height={40} items={display.cash.map((c) => ({ key: c.kind, amount: c.amountCents, fill: BAND[c.kind] }))} />
        <div style={{ marginTop: 14 }}>
          {display.cash.map((c) => (
            <div className="row" key={c.kind}>
              <span className={`marker ${c.amountCents > 0 ? "" : "hollow"}`} style={{ background: c.amountCents > 0 ? CASH_ACCENT[c.kind] : "transparent" }} />
              <span className="title">{TILE_TITLE[c.kind]}</span>
              <span className="value" style={{ color: c.amountCents > 0 ? CASH_ACCENT[c.kind] : "var(--text-2)" }}>{moneyExact(c.amountCents)}</span>
            </div>
          ))}
        </div>
      </section>

      {display.debts.map((debt) => <DebtSection key={debt.id} debt={debt} display={display} onWhy={why} />)}

      <EmergencySection display={display} onWhy={why} />

      <section className="section">
        <SectionHeader title="Target-date foundation" onWhy={why} />
        <div style={{ display: "flex", alignItems: "center", gap: 36, marginBottom: 22 }}>
          <AllocationRing stocks={display.equityWeight} />
          <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
            <Legend color="var(--accent)" title="Stocks" value={percent(display.equityWeight)} />
            <Legend color="var(--bonds)" title="Bonds" value={percent(1 - display.equityWeight)} />
          </div>
        </div>
        <p className="caption" style={{ fontSize: 13 }}>{DISCLOSURE.allocationCopy}</p>
        <p className="caption" style={{ color: "var(--quiet)", marginTop: 8 }}>{DISCLOSURE.allocationLabel}.</p>
      </section>
    </div>
  );
}

function DebtSection({ debt, display, onWhy }: { debt: DisplayDebt; display: Display; onWhy: () => void }) {
  const payoff = display.evaluation.projections.adaptive.debt_free_month;
  const title = debt.name === "Credit card" ? "Credit card debt" : debt.name;
  return (
    <section className="section">
      <SectionHeader title={title} onWhy={onWhy} />
      <div style={{ display: "flex", alignItems: "baseline", marginBottom: 24 }}>
        <Figure size={40}>{money(debt.balanceCents)}</Figure>
        <span className="chip muted" style={{ marginLeft: "auto" }}>{percent(debt.apr)} APR</span>
      </div>
      <SegmentedBand segments={[
        { label: "Minimum", value: money(debt.minimumCents), weight: debt.minimumCents, fill: BAND.minimum },
        ...(debt.extraCents > 0 ? [{ label: "Extra", value: moneyExact(debt.extraCents), weight: debt.extraCents, fill: BAND.debt }] : []),
      ]} />
      <div style={{ display: "flex", gap: 16, marginTop: 18 }}>
        <Stat value={moneyExact(debt.minimumCents + debt.extraCents)} unit="/ mo" caption="Total payment" />
        {debt.extraCents > 0 && payoff !== null && payoff > 0 && (
          <Stat value={monthLabel(display.profile.as_of_date, payoff)} caption="Projected payoff" align="right" icon="flag" />
        )}
      </div>
      <p className="caption" style={{ fontSize: 13, marginTop: 16 }}>
        {debt.extraCents > 0
          ? "After this debt is paid off, rebuild savings before increasing contributions."
          : `At ${percent(debt.apr)} APR, the minimum payment keeps this on schedule without slowing saving.`}
      </p>
    </section>
  );
}

function EmergencySection({ display, onWhy }: { display: Display; onWhy: () => void }) {
  const m = display.emergencyMonths;
  const starterFunded = m >= display.starterMonths;
  const fullFunded = m >= display.fullMonths;
  const beyond = m - display.fullMonths;
  return (
    <section className="section">
      <SectionHeader title="Emergency savings" onWhy={onWhy} />
      <div style={{ display: "flex", alignItems: "baseline", marginBottom: 24 }}>
        <Figure size={40}>{months(m)}</Figure>
        <span className="num" style={{ marginLeft: "auto", color: "var(--text-2)", fontWeight: 500 }}>{money(display.profile.emergency_cash_cents)}</span>
      </div>
      <MonthMeter months={m} target={display.fullMonths} />
      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 12 }}>
        <Target title={`Starter · ${display.starterMonths} mo`} funded={starterFunded} value={money(display.starterTargetCents)} />
        <Target title={`Full target · ${display.fullMonths} mo`} funded={fullFunded} value={money(display.fullTargetCents)} right />
      </div>
      {beyond > 0 && <p className="caption" style={{ fontSize: 13, marginTop: 14 }}>{months(beyond)} beyond target</p>}
    </section>
  );
}

function Target({ title, funded, value, right }: { title: string; funded: boolean; value: string; right?: boolean }) {
  return (
    <div style={{ textAlign: right ? "right" : "left" }}>
      <div className="caption">{title}</div>
      <div style={{ display: "flex", alignItems: "center", gap: 4, justifyContent: right ? "flex-end" : "flex-start",
        color: funded ? "var(--accent)" : "var(--text)", fontSize: 14, fontWeight: 500, marginTop: 3 }} className="num">
        {funded && <Icon name="check" size={12} />} {funded ? "Funded" : value}
      </div>
    </div>
  );
}

function Legend({ color, title, value }: { color: string; title: string; value: string }) {
  return (
    <div>
      <span className="label" style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
        <i style={{ width: 7, height: 7, borderRadius: "50%", background: color, display: "inline-block" }} /> {title}
      </span>
      <div className="figure" style={{ fontSize: 26, marginTop: 2 }}>{value}</div>
    </div>
  );
}
