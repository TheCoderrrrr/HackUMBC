/**
 * Keeps the desktop's wire types in step with the backend contract. contracts/openapi.json is
 * regenerated from the FastAPI app (backend/tests/test_contracts.py fails if it's stale), so a
 * field added or removed on the backend fails here until types.ts matches.
 */
import { describe, expect, it } from "vitest";
import typesRaw from "./types.ts?raw";
import openapi from "../../../contracts/openapi.json";

const types = typesRaw.replace(/\r\n/g, "\n"); // checkouts may use CRLF
const schemas = (openapi as { components: { schemas: Record<string, { properties?: Record<string, unknown> }> } }).components.schemas;

function tsFields(name: string): Set<string> {
  const start = types.indexOf(`export interface ${name} {`);
  const block = start === -1 ? null : /\{([\s\S]*?)\n\}/.exec(types.slice(start));
  if (!block) throw new Error(`no interface ${name} in types.ts`);
  return new Set([...block[1].matchAll(/^ {2}(\w+)\??:/gm)].map((m) => m[1]));
}

const SHARED = [
  "FinancialProfile", "Scenario", "FinancialState", "ProjectionPoint", "Projection", "ModelAssumptions",
  "Evaluation", "Health", "RunSummary", "Comparison", "HistoryStatus", "PlanStyles", "StyleOutcome", "YearValues",
];

describe.each(SHARED)("%s", (name) => {
  it("has exactly the backend's fields", () => {
    const api = Object.keys(schemas[name]?.properties ?? {}).sort();
    expect(api.length).toBeGreaterThan(0);
    expect([...tsFields(name)].sort()).toEqual(api);
  });
});
