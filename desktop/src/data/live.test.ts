/**
 * Live sync check against a running backend (skipped unless ARM_API is set), e.g.
 *   ARM_API=http://127.0.0.1:8000 npx vitest run src/data/live.test.ts
 * Fresh /v1/evaluate and /v1/plan-styles responses must satisfy the same rules the charts rely on.
 */
import { describe, expect, it } from "vitest";
import type { Evaluation, FinancialProfile, PlanStyles } from "../api/types";
import { gapAt } from "./chart";
import { balanceAtYear, yearlyBalances } from "./display";

// Read without Node typings: this project compiles for the browser.
const API = (globalThis as { process?: { env: Record<string, string | undefined> } }).process?.env.ARM_API;

async function post<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(`${API}${path}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  expect(res.status).toBe(200);
  return (await res.json()) as T;
}

describe.skipIf(!API)("live backend", async () => {
  const profiles = API ? ((await (await fetch(`${API}/v1/demo-profiles`)).json()) as { profiles: FinancialProfile[] }).profiles : [];

  it.each(profiles.map((p) => [p.id, p] as const))("%s: evaluate matches the chart rules", async (_, profile) => {
    const evaluation = await post<Evaluation>("/v1/evaluate", { profile });
    const years = profile.retirement_age - profile.age;
    for (const strategy of ["current", "adaptive"] as const) {
      const projection = evaluation.projections[strategy];
      const engineYearly = projection.points.filter((p) => p.month % 12 === 0).map((p) => p.retirement_balance_cents);
      expect(yearlyBalances(projection, years)).toEqual(engineYearly.slice(0, years + 1));
      expect(balanceAtYear(projection, years)).toBe(projection.retirement_balance_nominal_cents);
    }
    const plan = yearlyBalances(evaluation.projections.adaptive, years);
    const habits = yearlyBalances(evaluation.projections.current, years);
    expect(gapAt(plan, habits, years)).toBe(
      evaluation.projections.adaptive.retirement_balance_nominal_cents! - evaluation.projections.current.retirement_balance_nominal_cents!,
    );
  }, 20_000);

  it.each(profiles.map((p) => [p.id, p] as const))("%s: plan-styles yearly values use the same sampling", async (_, profile) => {
    const styles = await post<PlanStyles>("/v1/plan-styles", { profile });
    for (const outcome of [styles.current, ...styles.styles]) {
      expect(outcome.yearly.map((y) => y.month)).toEqual(outcome.yearly.map((_, i) => 12 * i));
      expect(outcome.yearly[outcome.yearly.length - 1].retirement_balance_cents).toBe(outcome.retirement_balance_nominal_cents);
    }
  }, 20_000);

  it("history: save then delete a run (skipped when history is off)", async () => {
    const status = (await (await fetch(`${API}/v1/history/status`)).json()) as { enabled: boolean; available: boolean };
    if (!status.enabled || !status.available) return;
    const profile = profiles[0];
    const evaluation = await post<Evaluation>("/v1/evaluate", { profile });
    const res = await fetch(`${API}/v1/history/runs`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ profile_id: profile.id, scenario: null, decision_summary: evaluation.decision_summary, input_hash: evaluation.input_hash }),
    });
    expect([200, 201]).toContain(res.status);
    const { run } = (await res.json()) as { run: { run_id: string } };
    expect((await fetch(`${API}/v1/history/runs/${run.run_id}`, { method: "DELETE" })).status).toBe(204);
    expect((await fetch(`${API}/v1/history/runs/${run.run_id}`, { method: "DELETE" })).status).toBe(404);
  }, 30_000);

  it("people: add two, list, plan privately, update, erase one", async () => {
    const status = (await (await fetch(`${API}/v1/history/status`)).json()) as { enabled: boolean; available: boolean };
    if (!status.enabled || !status.available) return;
    const { formToInput, profileToForm } = await import("./numbers");
    const { newProfileKey } = await import("./profileKey");
    const base = profileToForm(profiles.find((p) => p.id === "morgan")!);
    const alex = formToInput({ ...base, name: "Alex" }).input!;
    const sam = formToInput({ ...base, name: "Sam", age: "28" }).input!;
    const key = newProfileKey(), stranger = newProfileKey();
    const h = (k: string) => ({ "content-type": "application/json", "x-profile-key": k });
    const create = async (form: unknown) => {
      const res = await fetch(`${API}/v1/profiles`, { method: "POST", headers: h(key), body: JSON.stringify(form) });
      expect(res.status).toBe(201);
      return ((await res.json()) as { profile: FinancialProfile }).profile;
    };

    const a = await create(alex), b = await create(sam);          // the bug: a second person must be addable
    expect(a.id).not.toBe(b.id);
    const listed = (await (await fetch(`${API}/v1/profiles`, { headers: h(key) })).json()) as { profiles: { profile: FinancialProfile }[] };
    expect(listed.profiles.map((p) => p.profile.name)).toEqual(["Alex", "Sam"]);
    expect(((await (await fetch(`${API}/v1/profiles`, { headers: h(stranger) })).json()) as { profiles: unknown[] }).profiles).toEqual([]);

    const evaluation = await post<Evaluation>("/v1/evaluate", { profile: b });
    const saved = await fetch(`${API}/v1/history/runs`, { method: "POST", headers: h(key), body: JSON.stringify({
      profile_id: b.id, scenario: null, decision_summary: evaluation.decision_summary, input_hash: evaluation.input_hash }) });
    expect(saved.status).toBe(201);
    const runs = async (k: string) => ((await (await fetch(`${API}/v1/history/runs?profile_id=${b.id}`, { headers: h(k) })).json()) as { runs: unknown[] }).runs;
    expect(await runs(key)).toHaveLength(1);
    expect(await runs(stranger)).toHaveLength(0);

    const updated = await fetch(`${API}/v1/profiles/${b.id}`, { method: "PUT", headers: h(key), body: JSON.stringify({ ...sam, age: 29 }) });
    expect(((await updated.json()) as { profile: FinancialProfile }).profile.age).toBe(29);

    for (const p of [a, b]) expect((await fetch(`${API}/v1/profiles/${p.id}`, { method: "DELETE", headers: h(key) })).status).toBe(204);
    expect(await runs(key)).toHaveLength(0);
  }, 60_000);
});

