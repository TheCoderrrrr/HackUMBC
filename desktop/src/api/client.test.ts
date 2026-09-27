import { afterEach, describe, expect, it, vi } from "vitest";
import { APIError, api } from "./client";

afterEach(() => vi.unstubAllGlobals());

describe("send", () => {
  it("treats 204 No Content as success (DELETE /v1/history/runs/{id})", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 204 })));
    await expect(api.history.remove("00000000-0000-0000-0000-000000000000")).resolves.toBeNull();
  });
  it("surfaces the backend's error envelope", async () => {
    const body = { error: { code: "RUN_NOT_FOUND", message: "That saved run doesn't exist.", field_paths: ["run_id"], retryable: false } };
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify(body), { status: 404 })));
    const err = await api.history.remove("x").catch((e) => e);
    expect(err).toBeInstanceOf(APIError);
    expect(err.kind).toBe("server");
    expect(err.body.code).toBe("RUN_NOT_FOUND");
  });
  it("reports an unreachable backend when the proxy answers 502 without JSON", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("Bad gateway", { status: 502 })));
    const err = await api.health().catch((e) => e);
    expect(err.kind).toBe("unreachable");
  });
});
