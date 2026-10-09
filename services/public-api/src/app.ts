// Dry Run public API. PUBLIC INFORMATION ONLY.
// There are deliberately no household/home endpoints. Only GET/HEAD; no query parameters; no bodies;
// path parameters are allowlisted. The service does not log request details.
import { Hono } from "hono";
import type { Context, Next } from "hono";
import { AlertsEnvelope, RegionPack, type AlertsEnvelopeT, type RegionPackT, type RegionInfoT } from "./schema";
import { fetchNWSAlerts, UpstreamError, type NWSDeps } from "./nws";
import { FixtureFloodHazardProvider, type FloodHazardProvider } from "./fema";
import { TTLCache } from "./cache";

export interface ContentBundle {
  contentManifest: { contentVersion: string; [k: string]: unknown };
  localeManifest: unknown;
  sources: { sources: Array<{ id: string; [k: string]: unknown }>; [k: string]: unknown };
  regionPacks: unknown[];
  locales: Record<string, Record<string, Record<string, string>>>;
}

export interface AppDeps {
  bundle: ContentBundle;
  nws: NWSDeps;
  flood?: FloodHazardProvider;
}

const LOCALES = new Set(["en", "es", "vi"]);
const VERSION = /^[A-Za-z0-9._-]{1,40}$/;
const SOURCE_ID = /^S\d{2,3}$/;

export function loadPacks(bundle: ContentBundle): RegionPackT[] {
  // Invalid bundled content is a deployment bug: fail loudly at startup rather than serve it.
  return bundle.regionPacks.map((p) => RegionPack.parse(p));
}

export function createApp(deps: AppDeps) {
  const packs = loadPacks(deps.bundle);
  const regionIndex = new Map<string, { info: RegionInfoT; pack: RegionPackT }>();
  for (const pack of packs) for (const info of pack.regions) regionIndex.set(info.id, { info, pack });
  const alertCache = new TTLCache<AlertsEnvelopeT>();
  const flood = deps.flood ?? new FixtureFloodHazardProvider();
  const app = new Hono();

  // ---- Request hygiene -------------------------------------------------------------------
  app.use("*", async (c: Context, next: Next) => {
    if (c.req.method !== "GET" && c.req.method !== "HEAD") {
      return c.json({ error: "method_not_allowed" }, 405, { Allow: "GET, HEAD" });
    }
    const url = new URL(c.req.url);
    if (url.search.length > 0) return c.json({ error: "unexpected_query" }, 400);
    const len = c.req.header("content-length");
    if ((len && len !== "0") || c.req.header("transfer-encoding")) return c.json({ error: "unexpected_body" }, 400);
    await next();
    c.header("X-Content-Type-Options", "nosniff");
    c.header("Referrer-Policy", "no-referrer");
    c.header("Access-Control-Allow-Origin", "*");
  });

  // ---- Routes ----------------------------------------------------------------------------
  app.get("/v1/health", (c) => c.json({ status: "ok", contentVersion: deps.bundle.contentManifest.contentVersion }));

  app.get("/v1/manifest", (c) => {
    c.header("Cache-Control", "public, max-age=3600");
    return c.json({
      schemaVersion: 1,
      contentVersion: deps.bundle.contentManifest.contentVersion,
      packs: packs.map((p) => ({ packID: p.packID, contentVersion: p.contentVersion, generatedAt: p.generatedAt,
        expiresAt: p.expiresAt ?? null, classification: p.classification, regionIDs: p.regions.map((r) => r.id) })),
      locales: deps.bundle.localeManifest,
      sourceCount: deps.bundle.sources.sources.length,
      signed: false,
      note: "Unsigned public data. Safety rule content is bundled in the app; downloads are limited to validated public data.",
    });
  });

  app.get("/v1/regions/:regionID/pack", (c) => {
    const entry = regionIndex.get(c.req.param("regionID"));
    if (!entry) return c.json({ error: "unknown_region" }, 404);
    // Return the pack scoped to this region plus statewide resources it can use.
    const { info, pack } = entry;
    const resources = pack.resources.filter((r) => r.regionIDs.includes(info.id));
    const cited = new Set(resources.flatMap((r) => r.sourceIDs));
    const scoped: RegionPackT = { ...pack, packID: `${pack.packID}.${info.id}`.slice(0, 64), regions: [info], resources,
      sources: pack.sources.filter((s) => cited.has(s.id)) };
    if (scoped.sources.length === 0) scoped.sources = pack.sources.slice(0, 1);
    c.header("Cache-Control", "public, max-age=3600");
    return c.json(RegionPack.parse(scoped));
  });

  app.get("/v1/regions/:regionID/alerts", async (c) => {
    const entry = regionIndex.get(c.req.param("regionID"));
    if (!entry) return c.json({ error: "unknown_region" }, 404);
    const { info } = entry;
    const now = deps.nws.now();
    const ugc = [...info.nwsZoneIDs, ...info.nwsCountyIDs];
    if (ugc.length === 0) {
      return c.json(AlertsEnvelope.parse({ schemaVersion: 1, regionID: info.id, fetchedAt: now.toISOString(), status: "notSupported", alerts: [] }));
    }
    const cached = alertCache.get(info.id, now.getTime());
    if (cached) return c.json(cached);
    try {
      const { alerts, maxAgeSeconds } = await fetchNWSAlerts(ugc, deps.nws);
      const env = AlertsEnvelope.parse({ schemaVersion: 1, regionID: info.id, fetchedAt: now.toISOString(), status: "ok", alerts });
      alertCache.set(info.id, env, maxAgeSeconds * 1000, now.getTime());
      c.header("Cache-Control", `public, max-age=${maxAgeSeconds}`);
      return c.json(env);
    } catch (e) {
      // Never substitute demo or stale alerts as current. The client says "current conditions unavailable".
      const reason = e instanceof UpstreamError ? "upstream_unavailable" : "error";
      c.header("Cache-Control", "no-store");
      return c.json({ ...AlertsEnvelope.parse({ schemaVersion: 1, regionID: info.id, fetchedAt: now.toISOString(), status: "unavailable", alerts: [] }), reason }, 503);
    }
  });

  app.get("/v1/regions/:regionID/flood-context", async (c) => {
    const entry = regionIndex.get(c.req.param("regionID"));
    if (!entry) return c.json({ error: "unknown_region" }, 404);
    return c.json(await flood.context(entry.info.id));
  });

  app.get("/v1/content/:version/:locale", (c) => {
    const version = c.req.param("version");
    const locale = c.req.param("locale");
    if (!VERSION.test(version) || !LOCALES.has(locale)) return c.json({ error: "invalid_parameter" }, 400);
    if (version !== deps.bundle.contentManifest.contentVersion) return c.json({ error: "unknown_version" }, 404);
    c.header("Cache-Control", "public, max-age=86400");
    return c.json({ contentVersion: version, locale, domains: deps.bundle.locales[locale] ?? {}, manifest: deps.bundle.localeManifest });
  });

  app.get("/v1/sources/:sourceID", (c) => {
    const id = c.req.param("sourceID");
    if (!SOURCE_ID.test(id)) return c.json({ error: "invalid_parameter" }, 400);
    const s = deps.bundle.sources.sources.find((x) => x.id === id);
    if (!s) return c.json({ error: "unknown_source" }, 404);
    c.header("Cache-Control", "public, max-age=86400");
    return c.json(s);
  });

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((_e, c) => c.json({ error: "internal" }, 500)); // no request details logged or echoed
  return app;
}
