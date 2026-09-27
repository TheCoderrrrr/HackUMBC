import { useEffect, useMemo, useState, type ReactNode } from "react";
import { APIError, api, errorMessage } from "../api/client";
import type { DebtInput, ProfileBuild } from "../api/types";
import { Icon } from "../components/ui";
import { Term } from "../components/Term";
import { money, months, percent } from "../data/format";
import { EMPTY_FORM, formFieldFor, formToInput, inputToForm, profileToForm, type NumbersForm } from "../data/numbers";
import { ensureProfileKey, peekProfileKey } from "../data/profileKey";
import { savedProfiles } from "../data/saved";
import { useStore } from "../store";

type Preview =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ok"; data: ProfileBuild }
  | { status: "error"; message: string; field: string | null };

const BLOCKING: Record<string, string> = {
  MISSING_REQUIRED_INPUT: "Some details are unknown (for example your employer match), so the plan stops before retirement saving until you confirm them.",
  CASH_FLOW_SHORTFALL: "Your living costs and minimum payments are more than your take-home pay, so there's nothing to plan with yet.",
};

/**
 * "Your numbers": the user's own profile. Plain form fields in dollars and percents; the engine
 * previews what it sees as they type, and saving stores it in Tiger Data under an anonymous key.
 */
export function YourNumbers() {
  const { mine, numbers, upsertMine, removeMine, closeNumbers, liveEnabled, setTab } = useStore();
  const editing = numbers?.id ? mine.find((m) => m.profile.id === numbers.id) ?? null : null;
  const [form, setForm] = useState<NumbersForm>(() => (editing ? inputToForm(editing.form) : EMPTY_FORM));
  const [preview, setPreview] = useState<Preview>({ status: "idle" });
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [confirmErase, setConfirmErase] = useState(false);
  const { input, missing } = useMemo(() => formToInput(form), [form]);
  const inputJson = input ? JSON.stringify(input) : null;

  // Ask the engine what it sees, a moment after typing stops.
  useEffect(() => {
    if (!input || !liveEnabled) {
      setPreview({ status: "idle" });
      return;
    }
    const controller = new AbortController();
    setPreview({ status: "loading" });
    const timer = setTimeout(() => {
      api.profiles.build(input, controller.signal)
        .then((data) => setPreview({ status: "ok", data }))
        .catch((error: unknown) => {
          if (controller.signal.aborted) return;
          const path = error instanceof APIError ? error.body?.field_paths?.[0] : undefined;
          setPreview({ status: "error", message: errorMessage(error), field: path ? formFieldFor(path) : null });
        });
    }, 450);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [inputJson, liveEnabled]); // eslint-disable-line react-hooks/exhaustive-deps

  const set = (patch: Partial<NumbersForm>) => {
    setForm((f) => ({ ...f, ...patch }));
    setSaveError(null);
  };
  const setDebt = (i: number, patch: Partial<NumbersForm["debts"][number]>) =>
    set({ debts: form.debts.map((d, j) => (j === i ? { ...d, ...patch } : d)) });
  const errorFor = (field: string) =>
    preview.status === "error" && preview.field === field ? preview.message : null;

  const save = async () => {
    if (!input) return;
    setSaving(true);
    setSaveError(null);
    try {
      const key = ensureProfileKey();
      const built = editing ? await api.profiles.update(editing.profile.id, input, key) : await api.profiles.create(input, key);
      upsertMine({ form: input, profile: built.profile });
      closeNumbers();
      setTab("overview");
    } catch (error) {
      setSaveError(errorMessage(error));
    } finally {
      setSaving(false);
    }
  };
  const erase = async () => {
    if (!editing) return;
    const key = peekProfileKey();
    try {
      if (key) await api.profiles.erase(editing.profile.id, key);
    } catch (error) {
      if (!(error instanceof APIError && error.body?.code === "PROFILE_NOT_FOUND")) {
        setSaveError(errorMessage(error));
        return;
      }
    }
    removeMine(editing.profile.id);
    closeNumbers();
  };
  const cancel = () => closeNumbers();
  const morgan = savedProfiles.find((p) => p.id === "morgan");
  const canSave = Boolean(input) && preview.status === "ok" && !saving;

  return (
    <div className="numbers fade-in">
      <div className="numbers-intro">
        <div>
          <h2 className="h-section">{editing ? `Edit ${editing.profile.name}'s numbers` : "Add a person"}</h2>
          <p className="body" style={{ fontSize: 14, marginTop: 4 }}>
            About two minutes. Rough figures are fine; you can change them anytime. ARM uses them to build your plan.
          </p>
        </div>
        {morgan && (
          <button className="pill neutral" onClick={() => set(profileToForm(morgan))}>
            <Icon name="replay" /> Start from Morgan's numbers
          </button>
        )}
      </div>

      <div className="numbers-grid">
        <div className="stack" style={{ gap: 18 }}>
          <Group n={1} title="About you">
            <Field label="Name" hint="Optional" value={form.name} onChange={(v) => set({ name: v })} placeholder="You" />
            <Field label="Age" value={form.age} onChange={(v) => set({ age: v })} error={errorFor("age")} missing={missing.includes("age")} />
            <Field label="Retire at" value={form.retirementAge} onChange={(v) => set({ retirementAge: v })}
              error={errorFor("retirementAge")} missing={missing.includes("retirementAge")} />
          </Group>

          <Group n={2} title="Income and spending">
            <Field label="Salary" hint="per year, before tax" prefix="$" value={form.salary} onChange={(v) => set({ salary: v })}
              error={errorFor("salary")} missing={missing.includes("salary")} />
            <Field label="Take-home pay" hint="per month, after tax" prefix="$" value={form.takeHome} onChange={(v) => set({ takeHome: v })}
              error={errorFor("takeHome")} missing={missing.includes("takeHome")} />
            <Field label="Living costs" hint="per month: rent, food, bills" prefix="$" value={form.living} onChange={(v) => set({ living: v })}
              error={errorFor("living")} missing={missing.includes("living")} />
          </Group>

          <Group n={3} title="Savings">
            <Field label="Retirement savings" hint="401(k) and IRA balances today" prefix="$" value={form.retirementBalance}
              onChange={(v) => set({ retirementBalance: v })} error={errorFor("retirementBalance")} missing={missing.includes("retirementBalance")} />
            <Field label="You contribute" hint="of your pay" suffix="%" value={form.contribution} onChange={(v) => set({ contribution: v })}
              error={errorFor("contribution")} missing={missing.includes("contribution")} />
            <Field label={<Term id="emergency-fund">Emergency cash</Term>} hint="savings you can reach quickly" prefix="$" value={form.emergencyCash}
              onChange={(v) => set({ emergencyCash: v })} error={errorFor("emergencyCash")} missing={missing.includes("emergencyCash")} />
          </Group>

          <Group n={4} title={<Term id="employer-match">Employer match</Term>}>
            <div className="segmented" style={{ gridColumn: "1 / -1" }}>
              {([["match", "My employer matches"], ["none", "No match"], ["unknown", "Not sure"]] as const).map(([k, label]) => (
                <button key={k} aria-pressed={form.matchKind === k} onClick={() => set({ matchKind: k })}>{label}</button>
              ))}
            </div>
            {form.matchKind === "match" && (
              <>
                <Field label="They add" hint="of each dollar you put in (100 = dollar for dollar)" suffix="%" value={form.matchRate}
                  onChange={(v) => set({ matchRate: v })} error={errorFor("matchRate")} missing={missing.includes("matchRate")} />
                <Field label="Up to" hint="of your pay" suffix="%" value={form.matchUpTo} onChange={(v) => set({ matchUpTo: v })}
                  error={errorFor("matchUpTo")} missing={missing.includes("matchUpTo")} />
              </>
            )}
          </Group>

          <Group n={5} title="Debts" note="Leave empty if you have none. Mortgages aren't included in this prototype.">
            {form.debts.map((d, i) => (
              <div key={i} className="debt-row">
                <label className="field">
                  <span className="field-label">Type</span>
                  <select value={d.type} onChange={(e) => setDebt(i, { type: e.target.value as DebtInput["type"] })}>
                    <option value="credit_card">Credit card</option>
                    <option value="student_loan">Student loan</option>
                    <option value="other">Other loan</option>
                  </select>
                </label>
                <Field label="Balance" prefix="$" value={d.balance} onChange={(v) => setDebt(i, { balance: v })}
                  error={errorFor(`debts.${i}.balance`)} missing={missing.includes(`debts.${i}.balance`)} />
                <Field label={<Term id="apr">APR</Term>} suffix="%" value={d.apr} onChange={(v) => setDebt(i, { apr: v })}
                  error={errorFor(`debts.${i}.apr`)} missing={missing.includes(`debts.${i}.apr`)} />
                <Field label="Minimum" hint="per month" prefix="$" value={d.minimum} onChange={(v) => setDebt(i, { minimum: v })}
                  error={errorFor(`debts.${i}.minimum`)} missing={missing.includes(`debts.${i}.minimum`)} />
                <button className="link debt-remove" onClick={() => set({ debts: form.debts.filter((_, j) => j !== i) })}
                  aria-label={`Remove debt ${i + 1}`}>Remove</button>
              </div>
            ))}
            {form.debts.length < 20 && (
              <button className="pill neutral" style={{ gridColumn: "1 / -1", justifySelf: "start" }}
                onClick={() => set({ debts: [...form.debts, { type: "credit_card", balance: "", apr: "", minimum: "" }] })}>
                + Add a debt
              </button>
            )}
          </Group>
        </div>

        <aside className="numbers-side">
          <section className="glass card">
            <p className="eyebrow" style={{ padding: 0 }}>What ARM sees</p>
            <PreviewPanel preview={preview} missing={missing.length} live={liveEnabled} />
            <button className="btn-primary full" style={{ marginTop: 18 }} onClick={save} disabled={!canSave}>
              {saving ? <span className="spinner" /> : <Icon name="check" />} {editing ? "Save changes" : "Save and build the plan"}
            </button>
            {saveError && <p className="caption goal-error" style={{ marginTop: 8 }}>{saveError}</p>}
            <button className="link" style={{ marginTop: 12 }} onClick={cancel}>Cancel</button>
          </section>
          <p className="caption numbers-privacy">
            <Icon name="seal" size={13} /> Saved in Tiger Data under an anonymous key kept in this browser: no email or account.
            The server stores only a hash of the key. {editing && (confirmErase ? (
              <span className="numbers-erase">Erase {editing.profile.name}'s numbers and saved plans?{" "}
                <button className="link" onClick={() => setConfirmErase(false)}>Keep</button>{" "}
                <button className="pill danger" onClick={erase}>Erase</button></span>
            ) : <button className="link" onClick={() => setConfirmErase(true)}>Erase {editing.profile.name}</button>)}
          </p>
        </aside>
      </div>
    </div>
  );
}

function PreviewPanel({ preview, missing, live }: { preview: Preview; missing: number; live: boolean }) {
  if (!live) return <p className="body numbers-state">Turn on live calculation to preview and save your numbers.</p>;
  if (missing > 0) return <p className="body numbers-state">{missing} {missing === 1 ? "field" : "fields"} left. The engine's view appears here as you fill them in.</p>;
  if (preview.status === "loading" || preview.status === "idle") return <p className="caption numbers-state"><span className="spinner" /> Checking your numbers…</p>;
  if (preview.status === "error") return <p className="body numbers-state numbers-bad">{preview.message}</p>;
  const s = preview.data.preview;
  return (
    <div className="fade-in">
      <dl className="numbers-facts">
        <div><dt>Available each month after essentials and minimum payments</dt><dd>{money(s.monthly_allocatable_budget_cents)}</dd></div>
        <div><dt>Emergency cash covers</dt><dd>{months(s.emergency_months)}</dd></div>
        <div><dt>Full employer match needs</dt><dd>{s.employee_rate_for_full_match === null ? "No match" : percent(s.employee_rate_for_full_match)}</dd></div>
        <div><dt>High-interest debt</dt><dd>{money(s.high_interest_debt_cents)}</dd></div>
        <div><dt>Years until retirement</dt><dd>{Math.round(s.months_until_retirement / 12)}</dd></div>
      </dl>
      {preview.data.blocking_issue && (
        <p className="guide-callout" style={{ marginTop: 12 }}>{BLOCKING[preview.data.blocking_issue] ?? preview.data.blocking_issue}</p>
      )}
    </div>
  );
}

function Group({ n, title, note, children }: { n: number; title: ReactNode; note?: string; children: ReactNode }) {
  return (
    <section className="section numbers-group">
      <h3 className="numbers-group-title"><span className="fs-num">{n}</span>{title}</h3>
      {note && <p className="caption" style={{ marginTop: 4 }}>{note}</p>}
      <div className="numbers-fields">{children}</div>
    </section>
  );
}

function Field({ label, hint, value, onChange, prefix, suffix, placeholder, error, missing }: {
  label: ReactNode;
  hint?: string;
  value: string;
  onChange: (value: string) => void;
  prefix?: string;
  suffix?: string;
  placeholder?: string;
  error?: string | null;
  missing?: boolean;
}) {
  return (
    <label className={`field ${error ? "invalid" : ""}`}>
      <span className="field-label">{label}{hint && <span className="field-hint"> · {hint}</span>}</span>
      <span className="field-input">
        {prefix && <span className="field-affix">{prefix}</span>}
        <input inputMode="decimal" value={value} placeholder={placeholder ?? (missing ? "Required" : undefined)}
          onChange={(e) => onChange(e.target.value)} aria-invalid={Boolean(error)} />
        {suffix && <span className="field-affix">{suffix}</span>}
      </span>
      {error && <span className="field-error">{error}</span>}
    </label>
  );
}
