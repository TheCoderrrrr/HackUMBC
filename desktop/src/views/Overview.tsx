import { useState } from "react";
import { Icon, HeroAmount } from "../components/ui";
import { LineChart } from "../components/LineChart";
import { balanceAtYear, DISCLOSURE, yearlyBalances, type Display } from "../data/display";
import { asOfLabel, money, moneyExact, months, percent } from "../data/format";
import { useStore } from "../store";

export function Overview({ display }: { display: Display }) {
  const { setTab, setDrawer } = useStore();
  const [year, setYear] = useState<number | null>(null);
  const { profile, evaluation } = display;
  const years = display.yearsToRetirement;
  const startYear = Number(profile.as_of_date.slice(0, 4));
  const adaptive = evaluation.projections.adaptive;
  const balances = yearlyBalances(adaptive, years);
  const projected = (y: number) => (y === 0 ? profile.retirement_balance_cents : Math.round(balanceAtYear(adaptive, y) / 10000) * 10000);

  return (
    <div className="grid overview fade-in" key={profile.id}>
      <div className="stack">
        <section>
          <p className="h-card" style={{ color: year === null ? "var(--text)" : "var(--accent)", transition: "color .18s" }}>
            {year === null ? "Retirement savings" : `Projected at age ${profile.age + year}`}
          </p>
          <div style={{ marginTop: 10 }}>
            <HeroAmount cents={year === null ? profile.retirement_balance_cents : projected(year)} />
          </div>
          <p className="caption" style={{ marginTop: 8 }}>
            {year === null ? `As of ${asOfLabel(profile.as_of_date)}` : `${DISCLOSURE.illustrative} · ${startYear + year}`}
          </p>
        </section>

        <section className="glass card" style={{ paddingBottom: 18 }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 42 }}>
            <button className="pill" onClick={() => setTab("explore")}>
              <Icon name="explore" /> To age {profile.retirement_age} <Icon name="chevron" size={12} />
            </button>
            <span className="caption">Hover to scrub · {DISCLOSURE.illustrative.toLowerCase()}</span>
          </div>
          <LineChart
            height={240}
            series={[{ name: "Retirement savings", values: balances, color: "var(--accent)", area: true, width: 2.4 }]}
            onIndex={setYear}
            renderTooltip={(i) => <>Age {profile.age + i} · <b>{money(projected(i))}</b></>}
          />
          <div className="axis">
            <span>Today</span>
            <span>{startYear + years} · Age {profile.retirement_age}</span>
          </div>
        </section>

        <button className="section" onClick={() => setTab("plan")} style={{ textAlign: "left" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 18 }}>
            <h2 className="h-card">Planned monthly contributions</h2>
            <span style={{ color: "var(--caption)" }}><Icon name="chevron" size={16} /></span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 24 }}>
            <Contribution icon="person" title="You" cents={display.employeeCents} caption={`${percent(display.rate)} of salary`} />
            <Contribution icon="building" title="Employer" cents={display.employerCents}
              caption={display.matchCaptured ? "Full match" : display.employerCents === null ? "Depends on the final rate" : "Partial match"} />
          </div>
        </button>
      </div>

      <div className="stack">
        <section className="glass tint-green card">
          <p className="h-card" style={{ marginBottom: 14 }}>Your next step</p>
          <p style={{ fontSize: 20, fontWeight: 500, letterSpacing: -0.4, lineHeight: 1.3 }}>{display.nextStep.headline}</p>
          <p className="body" style={{ marginTop: 8, fontSize: 14 }}>
            {display.nextStep.amountCents !== null && <span className="strong num">{moneyExact(display.nextStep.amountCents)}</span>}
            {display.nextStep.detail}
          </p>
          <button className="pill" style={{ marginTop: 18 }} onClick={() => setDrawer("explanation")}>
            <Icon name="why" /> Why this plan? <Icon name="arrow" size={13} />
          </button>
        </section>

        <section>
          <div className="row" style={{ minHeight: 64 }}>
            <div>
              <p style={{ fontSize: 16, fontWeight: 400 }}>Emergency savings</p>
              <p className="label" style={{ fontSize: 12, marginTop: 3 }}>
                <span className="num strong" style={{ color: "var(--text-2)" }}>{money(profile.emergency_cash_cents)}</span> set aside
              </p>
            </div>
            <span className="num" style={{ fontSize: 20, fontWeight: 500 }}>{months(display.emergencyMonths)}</span>
          </div>
          <hr className="hairline" />
          <LinkRow icon="doc" title="Financial snapshot" onClick={() => setDrawer("snapshot")} />
          <hr className="hairline" />
          <LinkRow icon="sliders" title="Modeling assumptions" onClick={() => setDrawer("assumptions")} />
          <hr className="hairline" />
        </section>

        <button className="btn-primary full" onClick={() => setTab("plan")}>
          <Icon name="plan" /> View your plan
        </button>
        <p className="caption">{display.origin} · {DISCLOSURE.fictional}</p>
      </div>
    </div>
  );
}

function Contribution({ icon, title, cents, caption }: { icon: string; title: string; cents: number | null; caption: string }) {
  return (
    <div>
      <span className="label" style={{ display: "inline-flex", gap: 6, alignItems: "center" }}><Icon name={icon} size={13} /> {title}</span>
      <div className="figure" style={{ fontSize: 30, letterSpacing: -0.6, marginTop: 6 }}>{cents === null ? "—" : moneyExact(cents)}</div>
      <div className="caption" style={{ marginTop: 4 }}>{caption}</div>
    </div>
  );
}

function LinkRow({ icon, title, onClick }: { icon: string; title: string; onClick: () => void }) {
  return (
    <button onClick={onClick} style={{ display: "flex", alignItems: "center", gap: 9, width: "100%", minHeight: 52, color: "var(--accent)", fontSize: 15, fontWeight: 500 }}>
      <Icon name={icon} size={16} /> {title}
      <span style={{ marginLeft: "auto", display: "flex" }}><Icon name="chevron" size={15} /></span>
    </button>
  );
}
