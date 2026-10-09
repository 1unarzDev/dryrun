import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";

import { createApp, loadPacks, type ContentBundle } from "../src/app";
import { AlertsEnvelope, RegionPack } from "../src/schema";
import { buildAlertsURL, normalizeNWS, NWS_ORIGIN } from "../src/nws";
import bundleJSON from "../src/generated/bundle.json";

const bundle = bundleJSON as unknown as ContentBundle;
const CANARY = "CANARY-7f3a-PRIVATE-HOUSEHOLD-ALIAS";
const fixture = (name: string) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"));
const recorded = fixture("nws-alerts-tx-recorded.json");

function nwsBodyFor(zones: string[], overrides: Record<string, unknown> = {}) {
  // Synthetic copy of a recorded NWS feature, re-targeted at given UGC codes (test-only).
  const f = structuredClone(recorded.features[0]);
  f.properties.geocode.UGC = zones;
  Object.assign(f.properties, overrides);
  return { type: "FeatureCollection", features: [f] };
}

function makeApp(fetchImpl: typeof fetch, now = new Date("2026-10-09T19:00:00Z")) {
  const calls: string[] = [];
  const spy = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push(String(input));
    return fetchImpl(input, init);
  });
  const app = createApp({ bundle, nws: { fetch: spy as unknown as typeof fetch, userAgent: "DryRun-test", timeoutMs: 200, now: () => now } });
  return { app, calls, spy };
}

const okJSON = (body: unknown, headers: Record<string, string> = {}) => async () =>
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/geo+json", "cache-control": "public, max-age=60", ...headers } });

describe("contract fixtures", () => {
  it("bundled region packs validate", () => {
    const packs = loadPacks(bundle);
    expect(packs.map((p) => p.packID).sort()).toEqual(["tx-25-counties", "tx-statewide"]);
    const tx25 = packs.find((p) => p.packID === "tx-25-counties")!;
    expect(tx25.regions).toHaveLength(13);
    for (const r of packs.flatMap((p) => p.resources)) expect(r.activation).not.toBe("active");
  });

  it("shared alerts fixture validates (also decoded by Swift PublicDataContractTests)", () => {
    const env = AlertsEnvelope.parse(fixture("contract-alerts.json"));
    expect(env.alerts[0].classification).toBe("demo");
  });

  it("pack with a resource citing an unknown source is rejected", () => {
    const p = structuredClone(bundle.regionPacks[0]) as any;
    p.resources[0].sourceIDs = ["S99"];
    expect(RegionPack.safeParse(p).success).toBe(false);
  });

  it("pack with unexpected (e.g. private) keys is rejected", () => {
    const p = structuredClone(bundle.regionPacks[0]) as any;
    p.householdAlias = CANARY;
    expect(RegionPack.safeParse(p).success).toBe(false);
  });

  it("activation without expiry is rejected", () => {
    const p = structuredClone(bundle.regionPacks[1]) as any;
    p.resources[0].activation = "active";
    expect(RegionPack.safeParse(p).success).toBe(false);
  });
});

describe("request hygiene", () => {
  const { app } = makeApp(async () => { throw new Error("no network in this test"); });

  it("health and manifest work", async () => {
    expect((await app.request("/v1/health")).status).toBe(200);
    const m = await (await app.request("/v1/manifest")).json() as any;
    expect(m.signed).toBe(false);
    expect(m.packs.length).toBe(2);
  });

  it("there is no household or home endpoint and no POST", async () => {
    for (const path of ["/v1/household", "/v1/home", "/v1/households/hh-oak"]) {
      expect((await app.request(path)).status).toBe(404);
    }
    const post = await app.request("/v1/regions/48143/pack", { method: "POST", body: JSON.stringify({ alias: CANARY }) });
    expect(post.status).toBe(405);
  });

  it("rejects any query string, including private-looking keys", async () => {
    for (const q of [`?address=${CANARY}`, "?lat=32.2&lon=-98.2", "?x=1"]) {
      const r = await app.request(`/v1/regions/48143/pack${q}`);
      expect(r.status).toBe(400);
      expect(await r.text()).not.toContain(CANARY);
    }
  });

  it("rejects GET with a body", async () => {
    const r = await app.request(new Request("http://x/v1/health", { method: "GET", headers: { "content-length": "12" } }));
    expect(r.status).toBe(400);
  });

  it("only allowlisted regions, locales, versions, and source IDs", async () => {
    expect((await app.request("/v1/regions/06037/pack")).status).toBe(404);
    expect((await app.request(`/v1/regions/${encodeURIComponent("123 Main St")}/pack`)).status).toBe(404);
    expect((await app.request("/v1/content/2026.10.0/fr")).status).toBe(400);
    expect((await app.request("/v1/content/9.9.9/en")).status).toBe(404);
    expect((await app.request("/v1/sources/S27")).status).toBe(200);
    expect((await app.request("/v1/sources/http:%2F%2Fevil")).status).toBe(400);
    expect((await app.request("/v1/sources/S99")).status).toBe(404);
  });

  it("region pack is scoped and valid", async () => {
    const r = await app.request("/v1/regions/48143/pack");
    const pack = RegionPack.parse(await r.json());
    expect(pack.regions.map((x) => x.id)).toEqual(["48143"]);
    expect(pack.resources.every((x) => x.regionIDs.includes("48143"))).toBe(true);
  });

  it("FEMA flood context is labelled fixture, not live", async () => {
    const body = await (await app.request("/v1/regions/48143/flood-context")).json() as any;
    expect(body.classification).toBe("fixture");
    expect(body.note).toMatch(/not current flooding/);
  });
});

describe("NWS alerts adapter", () => {
  it("builds only fixed-origin URLs from official UGC codes (no SSRF)", () => {
    expect(buildAlertsURL(["TXZ130", "TXC143"])).toBe(`${NWS_ORIGIN}/alerts/active?zone=TXC143,TXZ130`);
    expect(() => buildAlertsURL(["http://169.254.169.254/"])).toThrow();
    expect(() => buildAlertsURL(["TXZ130&url=evil"])).toThrow();
  });

  it("associates by official UGC codes, not area names, and keeps text unchanged", () => {
    const body = nwsBodyFor(["TXZ130"], { areaDesc: "Hood, TX" }); // misleading area name
    const out = normalizeNWS(body, ["TXZ131"], "2026-10-09T19:00:00Z"); // Hood's zone
    expect(out).toHaveLength(0);
    const kept = normalizeNWS(body, ["TXZ130"], "2026-10-09T19:00:00Z");
    expect(kept).toHaveLength(1);
    expect(kept[0].description).toBe(recorded.features[0].properties.description);
    expect(kept[0].instruction).toBe(recorded.features[0].properties.instruction ?? null);
    expect(kept[0].sent).not.toBe(kept[0].fetchedAt);
  });

  it("drops non-Actual (exercise/test) messages and skips malformed features", () => {
    const body = nwsBodyFor(["TXZ130"], { status: "Exercise" });
    (body.features as unknown[]).push({ id: "bad", properties: { event: 3 } });
    expect(normalizeNWS(body, ["TXZ130"], "t")).toHaveLength(0);
  });

  it("recorded real response for coastal zones yields nothing for an inland county", () => {
    expect(normalizeNWS(recorded, ["TXZ130", "TXC143"], "t")).toHaveLength(0);
  });

  it("sends User-Agent, fetches only api.weather.gov, and never forwards client data", async () => {
    const { app, calls, spy } = makeApp(okJSON(nwsBodyFor(["TXZ130"])));
    const r = await app.request("/v1/regions/48143/alerts", { headers: { "X-Household": CANARY, Cookie: `a=${CANARY}` } });
    expect(r.status).toBe(200);
    const env = AlertsEnvelope.parse(await r.json());
    expect(env.alerts).toHaveLength(1);
    expect(env.alerts[0].classification).toBe("live");
    expect(calls).toHaveLength(1);
    expect(calls[0].startsWith(`${NWS_ORIGIN}/alerts/active?zone=`)).toBe(true);
    const init = spy.mock.calls[0][1] as RequestInit;
    expect(JSON.stringify(init)).not.toContain(CANARY);
    expect(calls[0]).not.toContain(CANARY);
    expect((init.headers as Record<string, string>)["User-Agent"]).toBe("DryRun-test");
  });

  it("caches within max-age, then refetches", async () => {
    let now = new Date("2026-10-09T19:00:00Z");
    const spy = vi.fn(okJSON(nwsBodyFor(["TXZ130"])));
    const app = createApp({ bundle, nws: { fetch: spy as unknown as typeof fetch, userAgent: "t", timeoutMs: 200, now: () => now } });
    await app.request("/v1/regions/48143/alerts");
    await app.request("/v1/regions/48143/alerts");
    expect(spy).toHaveBeenCalledTimes(1);
    now = new Date(now.getTime() + 61_000);
    await app.request("/v1/regions/48143/alerts");
    expect(spy).toHaveBeenCalledTimes(2);
  });

  it("upstream failure, malformed, or oversized responses return 'unavailable' with no alerts", async () => {
    const cases: Array<() => Promise<Response>> = [
      async () => { throw new TypeError("network down"); },
      async () => new Response("not json", { status: 200 }),
      async () => new Response("{}", { status: 500 }),
      async () => new Response(JSON.stringify({ features: "nope" }), { status: 200 }),
      async () => new Response("x".repeat(2_000_001), { status: 200 }),
    ];
    for (const impl of cases) {
      const { app } = makeApp(impl);
      const r = await app.request("/v1/regions/48143/alerts");
      expect(r.status).toBe(503);
      const body = await r.json() as any;
      expect(body.status).toBe("unavailable");
      expect(body.alerts).toEqual([]);
    }
  });

  it("times out a hanging upstream", async () => {
    const hang = (_: unknown, init?: RequestInit) => new Promise<Response>((_, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new Error("aborted")));
    });
    const { app } = makeApp(hang as unknown as typeof fetch);
    const r = await app.request("/v1/regions/48143/alerts");
    expect(r.status).toBe(503);
  });
});
