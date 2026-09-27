import { useCallback, useEffect, useMemo, useState } from "react";
import { api, errorMessage } from "../api/client";
import type { Comparison, Evaluation, HistoryStatus, RunSummary, Scenario, YearValues } from "../api/types";
import { Icon } from "../components/ui";
import { Disclosure } from "../components/Tabs";
import { LineChart, type Series } from "../components/LineChart";
import { money, monthLabel } from "../data/format";
import { peekProfileKey } from "../data/profileKey";
import { MY_ID, useStore } from "../store";

/** The result currently on screen: the plan as is, or a compared scenario. */
export interface Shown {
  evaluation: Evaluation;
  scenario: Scenario | null;
}

type State = { kind: "off" } | { kind: "checking" } | { kind: "ready"; status: HistoryStatus } | { kind: "error"; message: string };

const BASE_COLOR = "var(--blue)";
const OTHER_COLOR = "var(--accent)";

/** Leading values of a series; the shorter run simply ends earlier. */
function values(comparison: Comparison, side: "base" | "other"): number[] {
  const out: number[] = [];
  for (const year of comparison.years) {
    const v = year[side];
    if (!v) break;
    out.push(v.retirement_balance_cents);
  }
  return out;
}

function sourceLabel(run: RunSummary): string {
  return run.decision_source === "ai" ? "AI decision" : "Rules decision";
}

export function History({ shown }: { shown: Shown }) {
  const { liveEnabled, profile, style } = useStore();
  const [state, setState] = useState<State>({ kind: "checking" });
  const [runs, setRuns] = useState<RunSummary[]>([]);
  const [pick, setPick] = useState<{ base: string | null; other: string | null }>({ base: null, other: null });
  const [comparison, setComparison] = useState<Comparison | null>(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const ready = state.kind === "ready" && state.status.enabled && state.status.available;

  const loadRuns = useCallback(async (select?: string) => {
    const list = (await api.history.list(profile.id, undefined, keyFor(profile.id))).runs;
    setRuns(list);
    setPick((current) => {
      const ids = new Set(list.map((r) => r.run_id));
      const other = select ?? (current.other && ids.has(current.other) ? current.other : list[0]?.run_id ?? null);
      const keepBase = current.base && ids.has(current.base) && current.base !== other ? current.base : null;
      const base = keepBase ?? list.find((r) => r.run_id !== other)?.run_id ?? null;
      return { base, other };
    });
  }, [profile.id]);

  useEffect(() => {
    setRuns([]);
    setPick({ base: null, other: null });
    setComparison(null);
    setMessage(null);
    if (!liveEnabled) {
      setState({ kind: "off" });
      return;
    }
    const controller = new AbortController();
    setState({ kind: "checking" });
    api.history.status(controller.signal)
      .then(async (status) => {
        setState({ kind: "ready", status });
        if (status.enabled && status.available) await loadRuns();
      })
      .catch((error) => {
        if (!controller.signal.aborted) setState({ kind: "error", message: errorMessage(error) });
      });
    return () => controller.abort();
  }, [profile.id, liveEnabled, loadRuns]);

  useEffect(() => {
    setComparison(null);
    if (!ready || !pick.base || !pick.other || pick.base === pick.other) return;
    const controller = new AbortController();
    api.history.compare(pick.base, pick.other, controller.signal, keyFor(profile.id))
      .then(setComparison)
      .catch((error) => {
        if (!controller.signal.aborted) setMessage(errorMessage(error));
      });
    return () => controller.abort();
  }, [ready, pick.base, pick.other]);

  const save = async () => {
    setSaving(true);
    setMessage(null);
    try {
      const { run, created } = await api.history.save(shown.evaluation, shown.scenario, style, keyFor(profile.id));
      setMessage(created ? `Saved “${run.label}”.` : `“${run.label}” is already in history.`);
      await loadRuns(run.run_id);
    } catch (error) {
      setMessage(errorMessage(error));
    } finally {
      setSaving(false);
    }
  };

  const series = useMemo<Series[]>(() => comparison ? [
    { name: comparison.base.label, values: values(comparison, "base"), color: BASE_COLOR, dashed: true, width: 2 },
    { name: comparison.other.label, values: values(comparison, "other"), color: OTHER_COLOR, area: true, width: 2.4 },
  ] : [], [comparison]);

  const startYear = Number(profile.as_of_date.slice(0, 4));
  const shownLabel = shown.scenario ? "this scenario" : "the plan as is";

  return (
    <section className="section">
      <h2 className="h-section">Scenario history</h2>
      <p className="caption" style={{ marginTop: 3 }}>Saved runs, stored as time series in Tiger Data</p>

      {state.kind === "off" && <p className="body" style={{ marginTop: 14, fontSize: 14 }}>Turn on live calculation to save and compare runs.</p>}
      {state.kind === "checking" && <p className="caption" style={{ marginTop: 14 }}><span className="spinner" /></p>}
      {state.kind === "error" && <p className="body" style={{ marginTop: 14, fontSize: 14 }}>{state.message}</p>}
      {state.kind === "ready" && !state.status.enabled && (
        <p className="body" style={{ marginTop: 14, fontSize: 14 }}>Scenario history isn't set up on this server.</p>
      )}
      {state.kind === "ready" && state.status.enabled && !state.status.available && (
        <p className="body" style={{ marginTop: 14, fontSize: 14 }}>Scenario history is unavailable right now. Saved results still work.</p>
      )}

      {ready && (
        <>
          <div className="row" style={{ marginTop: 16 }}>
            <span className="label" style={{ fontSize: 14 }}>Save {shownLabel} to compare it later.</span>
            <button className="pill selected" style={{ height: 34, fontSize: 13 }} onClick={save} disabled={saving}>
              {saving ? <span className="spinner" /> : <Icon name="check" />} Save to history
            </button>
          </div>
          {message && <p className="caption fade-in" style={{ marginTop: 6 }}>{message}</p>}

          {runs.length < 2 ? (
            <p className="body" style={{ marginTop: 16, fontSize: 14 }}>
              {runs.length === 0 ? "No saved runs yet." : "Save one more run to compare the two over time."}
            </p>
          ) : null}
          {runs.length > 0 && (
            <Disclosure title="Manage saved runs" summary={`${runs.length} saved`}>
              <ul className="run-list">
                {runs.map((r) => <RunRow key={r.run_id} run={r} onDeleted={async (label) => {
                  setMessage(`Deleted “${label}”.`);
                  await loadRuns();
                }} onError={setMessage} />)}
              </ul>
            </Disclosure>
          )}
          {runs.length >= 2 && (
            <>
              <div className="history-pickers">
                <RunPicker label="Compare" color={BASE_COLOR} runs={runs} value={pick.base} disabled={pick.other}
                  onChange={(base) => setPick((p) => ({ ...p, base }))} />
                <RunPicker label="with" color={OTHER_COLOR} runs={runs} value={pick.other} disabled={pick.base}
                  onChange={(other) => setPick((p) => ({ ...p, other }))} />
              </div>
              {comparison && <ComparisonView comparison={comparison} series={series} startYear={startYear} age={profile.age} />}
            </>
          )}
        </>
      )}
    </section>
  );
}

function RunPicker({ label, color, runs, value, disabled, onChange }: {
  label: string;
  color: string;
  runs: RunSummary[];
  value: string | null;
  disabled: string | null;
  onChange: (id: string) => void;
}) {
  return (
    <label className="history-picker">
      <span className="label"><i style={{ borderTopColor: color }} /> {label}</span>
      <select value={value ?? ""} onChange={(e) => onChange(e.target.value)}>
        {runs.map((r) => (
          <option key={r.run_id} value={r.run_id} disabled={r.run_id === disabled}>
            {r.label} · saved {new Date(r.created_at).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}
          </option>
        ))}
      </select>
    </label>
  );
}

function pair(base: YearValues | null, other: YearValues | null, key: keyof YearValues) {
  const b = base ? money(base[key]) : "Retired";
  const o = other ? money(other[key]) : "Retired";
  return (
    <td>
      <span style={{ color: base ? "var(--text-2)" : "var(--quiet)" }}>{b}</span>
      <span className="caption"> → </span>
      <span style={{ color: other ? "var(--text)" : "var(--quiet)", fontWeight: 500 }}>{o}</span>
    </td>
  );
}

function ComparisonView({ comparison, series, startYear, age }: {
  comparison: Comparison;
  series: Series[];
  startYear: number;
  age: number;
}) {
  const span = Math.max(...series.map((s) => s.values.length - 1), 0);
  const { base, other } = comparison;
  return (
    <div className="fade-in">
      <div className="legend" style={{ margin: "18px 0 36px" }}>
        <span style={{ color: BASE_COLOR }}><i className="dashed" /> {base.label}</span>
        <span style={{ color: OTHER_COLOR, fontWeight: 500 }}><i /> {other.label}</span>
      </div>
      <LineChart height={210} series={series} renderTooltip={(i) => (
        <div style={{ display: "grid", gap: 3 }}>
          <span>{monthLabel(comparison.as_of_date, 12 * i)} · Age {age + i}</span>
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

      <table className="table" style={{ marginTop: 22 }}>
        <thead>
          <tr><th>In</th><th>Retirement</th><th>Emergency cash</th><th>Debt</th></tr>
        </thead>
        <tbody>
          {comparison.horizons.map((h) => (
            <tr key={h.years}>
              <td className="label">{h.years} years · {monthLabel(comparison.as_of_date, h.month)}</td>
              {pair(h.base, h.other, "retirement_balance_cents")}
              {pair(h.base, h.other, "cash_cents")}
              {pair(h.base, h.other, "debt_cents")}
            </tr>
          ))}
        </tbody>
      </table>
      <p className="caption" style={{ marginTop: 14 }}>
        From Tiger Data: yearly points of each run's time series (continuous aggregate). {sourceLabel(base)} → {sourceLabel(other)} ·
        model {other.model_version} · policy {other.policy_version}. Projected dates under illustrative assumptions, not observed data.
      </p>
    </div>
  );
}

/** One saved run with a delete button that asks once more before deleting. */
function RunRow({ run, onDeleted, onError }: {
  run: RunSummary;
  onDeleted: (label: string) => Promise<void>;
  onError: (message: string) => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const remove = async () => {
    setBusy(true);
    try {
      await api.history.remove(run.run_id, peekProfileKey());
      await onDeleted(run.label);
    } catch (error) {
      onError(errorMessage(error));
      setBusy(false);
      setConfirming(false);
    }
  };
  return (
    <li className="run-row">
      <span className="run-row-text">
        <b>{run.label}</b>
        <span className="caption">
          Saved {new Date(run.created_at).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}
          {run.final_retirement_balance_cents !== null && <> · {money(run.final_retirement_balance_cents)} at {run.retirement_age}</>}
          {" · "}{run.decision_source === "ai" ? "AI decision" : "Rules decision"}
        </span>
      </span>
      {confirming ? (
        <span className="run-row-actions">
          <button className="link" onClick={() => setConfirming(false)} disabled={busy}>Keep</button>
          <button className="pill danger" onClick={remove} disabled={busy}>{busy ? <span className="spinner" /> : "Delete"}</button>
        </span>
      ) : (
        <button className="pill neutral" onClick={() => setConfirming(true)} aria-label={`Delete ${run.label}`}>
          <Icon name="close" size={12} /> Delete
        </button>
      )}
    </li>
  );
}

/** The user's own plans are scoped to their anonymous key; demo plans are shared. */
function keyFor(profileID: string): string | null {
  return profileID === MY_ID ? peekProfileKey() : null;
}

