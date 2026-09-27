import type { CatalogSummary, FundShortlistEnvelope, FundShortlistQuery } from "./funds";
import type { ScreenContext } from "./chatContext";
import type {
  Comparison, ErrorBody, EvaluateRequest, Evaluation, FinancialProfile, Health, HistoryStatus, PlanningPreference,
  PlanStyles, ProfileBuild, ProfileInput, RunSummary, Scenario, StoredProfile,
} from "./types";

/** Header carrying the user's anonymous profile key (the server stores only its hash). */
const keyHeader = (key?: string | null): Record<string, string> => (key ? { "X-Profile-Key": key } : {});

/** Relative to the page; the Vite dev server forwards `/api/*` to the backend. */
const BASE = "/api";
export const EVALUATION_TIMEOUT_MS = 8000;
const CHAT_TIMEOUT_MS = 16000;
const REQUEST_TIMEOUT_MS = 5000;

export type EducationTurn = { role: "user" | "assistant"; content: string };
export type EducationReply = {
  answer: string;
  mode: "ai" | "template";
  topic: string;
  sources: { title: string; url: string }[];
};

export type APIErrorKind = "timedOut" | "cancelled" | "unreachable" | "server" | "unexpectedStatus" | "invalidResponse";

export class APIError extends Error {
  constructor(
    readonly kind: APIErrorKind,
    readonly status?: number,
    readonly body?: ErrorBody,
  ) {
    super(body?.message ?? kind);
  }

  get retryable(): boolean {
    switch (this.kind) {
      case "timedOut":
      case "unreachable":
        return true;
      case "server":
        return this.body?.retryable ?? false;
      case "unexpectedStatus":
        return (this.status ?? 0) >= 500;
      default:
        return false;
    }
  }
}

async function send<T>(path: string, init: RequestInit, timeoutMs: number, signal?: AbortSignal,
  extraHeaders: Record<string, string> = {}): Promise<T> {
  const controller = new AbortController();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);
  const onAbort = () => controller.abort();
  signal?.addEventListener("abort", onAbort);

  let response: Response;
  try {
    response = await fetch(BASE + path, {
      ...init,
      headers: { Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}), ...extraHeaders },
      signal: controller.signal,
    });
  } catch {
    if (timedOut) throw new APIError("timedOut");
    if (signal?.aborted) throw new APIError("cancelled");
    throw new APIError("unreachable");
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", onAbort);
  }

  // The dev proxy answers 502/504 with a non-JSON body when the backend is down.
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    if (body?.error?.code) throw new APIError("server", response.status, body.error as ErrorBody);
    if (response.status === 502 || response.status === 503 || response.status === 504) {
      throw new APIError("unreachable", response.status);
    }
    throw new APIError("unexpectedStatus", response.status);
  }
  if (response.status === 204) return null as T; // e.g. DELETE: success with no body
  try {
    return (await response.json()) as T;
  } catch {
    throw new APIError("invalidResponse", response.status);
  }
}

export const api = {
  health: (signal?: AbortSignal) => send<Health>("/health", { method: "GET" }, REQUEST_TIMEOUT_MS, signal),
  demoProfiles: (signal?: AbortSignal) =>
    send<{ schema_version: string; profiles: FinancialProfile[] }>(
      "/v1/demo-profiles",
      { method: "GET" },
      REQUEST_TIMEOUT_MS,
      signal,
    ),
  evaluate: (request: EvaluateRequest, signal?: AbortSignal) =>
    send<Evaluation>("/v1/evaluate", { method: "POST", body: JSON.stringify(request) }, EVALUATION_TIMEOUT_MS, signal),
  fundCatalog: (signal?: AbortSignal) =>
    send<CatalogSummary>("/v1/funds/catalog", { method: "GET" }, REQUEST_TIMEOUT_MS, signal),
  fundShortlist: (query: FundShortlistQuery, signal?: AbortSignal) =>
    send<FundShortlistEnvelope>("/v1/funds/shortlist", { method: "POST", body: JSON.stringify(query) }, REQUEST_TIMEOUT_MS, signal),
  educationChat: (message: string, history: EducationTurn[], context: ScreenContext, signal?: AbortSignal) =>
    send<EducationReply>("/v1/education/chat", {
      method: "POST", body: JSON.stringify({ message, history: history.slice(-4), context }),
    }, CHAT_TIMEOUT_MS, signal),
  /** Each plan style's own rule order through the engine; no AI, so fast and comparable. */
  planStyles: (profile: FinancialProfile, signal?: AbortSignal) =>
    send<PlanStyles>("/v1/plan-styles", { method: "POST", body: JSON.stringify({ profile }) }, REQUEST_TIMEOUT_MS, signal),
  history: {
    status: (signal?: AbortSignal) =>
      send<HistoryStatus>("/v1/history/status", { method: "GET" }, EVALUATION_TIMEOUT_MS, signal),
    /** Sends the inputs of a shown result; the server recomputes and stores its own numbers. */
    save: (evaluation: Evaluation, scenario: Scenario | null, style: PlanningPreference | null, key?: string | null) =>
      send<{ run: RunSummary; created: boolean }>("/v1/history/runs", {
        method: "POST",
        body: JSON.stringify({
          profile_id: evaluation.profile_id,
          scenario,
          decision_summary: evaluation.decision_summary,
          input_hash: evaluation.input_hash,
          planning_preference: style,
        }),
      }, EVALUATION_TIMEOUT_MS, undefined, keyHeader(key)),
    list: (profileID: string, signal?: AbortSignal, key?: string | null) =>
      send<{ runs: RunSummary[] }>(`/v1/history/runs?profile_id=${encodeURIComponent(profileID)}`,
        { method: "GET" }, REQUEST_TIMEOUT_MS, signal, keyHeader(key)),
    remove: (runID: string, key?: string | null) =>
      send<null>(`/v1/history/runs/${encodeURIComponent(runID)}`, { method: "DELETE" }, REQUEST_TIMEOUT_MS, undefined, keyHeader(key)),
    compare: (base: string, other: string, signal?: AbortSignal, key?: string | null) =>
      send<Comparison>(`/v1/history/compare?base=${encodeURIComponent(base)}&other=${encodeURIComponent(other)}`,
        { method: "GET" }, REQUEST_TIMEOUT_MS, signal, keyHeader(key)),
  },
  /** The user's own numbers: preview without storing, and store/load/erase under their key. */
  profiles: {
    build: (form: ProfileInput, signal?: AbortSignal) =>
      send<ProfileBuild>("/v1/profiles/build", { method: "POST", body: JSON.stringify(form) }, REQUEST_TIMEOUT_MS, signal),
    list: (key: string, signal?: AbortSignal) =>
      send<{ profiles: StoredProfile[] }>("/v1/profiles", { method: "GET" }, REQUEST_TIMEOUT_MS, signal, keyHeader(key)),
    create: (form: ProfileInput, key: string) =>
      send<ProfileBuild>("/v1/profiles", { method: "POST", body: JSON.stringify(form) }, REQUEST_TIMEOUT_MS, undefined, keyHeader(key)),
    update: (profileID: string, form: ProfileInput, key: string) =>
      send<ProfileBuild>(`/v1/profiles/${encodeURIComponent(profileID)}`, { method: "PUT", body: JSON.stringify(form) },
        REQUEST_TIMEOUT_MS, undefined, keyHeader(key)),
    erase: (profileID: string, key: string) =>
      send<null>(`/v1/profiles/${encodeURIComponent(profileID)}`, { method: "DELETE" }, REQUEST_TIMEOUT_MS, undefined, keyHeader(key)),
  },
};

export function errorMessage(error: unknown): string {
  if (!(error instanceof APIError)) return "Something went wrong. Try again.";
  switch (error.kind) {
    case "server":
      return error.body?.message ?? "The server rejected this request.";
    case "timedOut":
      return "The request took too long. Try again.";
    case "unreachable":
      return "Can't reach the backend. Saved results still work.";
    default:
      return "Something went wrong. Try again.";
  }
}
