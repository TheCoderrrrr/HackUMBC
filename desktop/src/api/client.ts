import type { CatalogSummary, FundShortlistEnvelope, FundShortlistQuery } from "./funds";
import type {
  Comparison, ErrorBody, EvaluateRequest, Evaluation, FinancialProfile, Health, HistoryStatus, RunSummary, Scenario,
} from "./types";

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

async function send<T>(path: string, init: RequestInit, timeoutMs: number, signal?: AbortSignal): Promise<T> {
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
      headers: { Accept: "application/json", ...(init.body ? { "Content-Type": "application/json" } : {}) },
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
  educationChat: (message: string, history: EducationTurn[], signal?: AbortSignal) =>
    send<EducationReply>("/v1/education/chat", {
      method: "POST", body: JSON.stringify({ message, history: history.slice(-4) }),
    }, CHAT_TIMEOUT_MS, signal),
  history: {
    status: (signal?: AbortSignal) =>
      send<HistoryStatus>("/v1/history/status", { method: "GET" }, REQUEST_TIMEOUT_MS, signal),
    /** Sends the inputs of a shown result; the server recomputes and stores its own numbers. */
    save: (evaluation: Evaluation, scenario: Scenario | null) =>
      send<{ run: RunSummary; created: boolean }>("/v1/history/runs", {
        method: "POST",
        body: JSON.stringify({
          profile_id: evaluation.profile_id,
          scenario,
          decision_summary: evaluation.decision_summary,
          input_hash: evaluation.input_hash,
        }),
      }, EVALUATION_TIMEOUT_MS),
    list: (profileID: string, signal?: AbortSignal) =>
      send<{ runs: RunSummary[] }>(`/v1/history/runs?profile_id=${encodeURIComponent(profileID)}`,
        { method: "GET" }, REQUEST_TIMEOUT_MS, signal),
    compare: (base: string, other: string, signal?: AbortSignal) =>
      send<Comparison>(`/v1/history/compare?base=${encodeURIComponent(base)}&other=${encodeURIComponent(other)}`,
        { method: "GET" }, REQUEST_TIMEOUT_MS, signal),
  },
};

export function errorMessage(error: unknown): string {
  if (!(error instanceof APIError)) return "Couldn't calculate this scenario.";
  switch (error.kind) {
    case "server":
      return error.body?.message ?? "The server rejected this request.";
    case "timedOut":
      return "The calculation took too long. Try again.";
    case "unreachable":
      return "Can't reach the backend. Saved results still work.";
    default:
      return "Couldn't calculate this scenario.";
  }
}
