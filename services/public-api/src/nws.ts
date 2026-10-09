// National Weather Service alerts adapter [S17]. Fixed host, fixed path; only official UGC IDs
// from our curated region packs are ever placed in the query (no caller-controlled URLs).
import { z } from "zod";
import type { PublicAlertT } from "./schema";

export const NWS_ORIGIN = "https://api.weather.gov";
export const MAX_NWS_BYTES = 2_000_000;

export interface NWSDeps {
  fetch: typeof fetch;
  userAgent: string;
  timeoutMs: number;
  now: () => Date;
}

const UGC = /^[A-Z]{2}[CZ]\d{3}$/;

// Lenient on fields we do not use; strict on the fields we display.
const NWSFeature = z.object({
  id: z.string(),
  properties: z.object({
    id: z.string(),
    event: z.string(),
    headline: z.string().nullable().optional(),
    description: z.string().nullable().optional(),
    instruction: z.string().nullable().optional(),
    severity: z.string(),
    areaDesc: z.string(),
    geocode: z.object({ UGC: z.array(z.string()).default([]) }).passthrough(),
    sent: z.string(),
    effective: z.string().nullable().optional(),
    expires: z.string().nullable().optional(),
    ends: z.string().nullable().optional(),
    status: z.string().optional(),
    messageType: z.string().optional(),
  }).passthrough(),
}).passthrough();

const NWSCollection = z.object({ features: z.array(z.unknown()) }).passthrough();

export class UpstreamError extends Error {}

export interface NWSResult {
  alerts: PublicAlertT[];
  maxAgeSeconds: number;
}

export function buildAlertsURL(ugcIDs: string[]): string {
  const ids = [...new Set(ugcIDs)].filter((id) => UGC.test(id)).sort();
  if (ids.length === 0 || ids.length > 10) throw new UpstreamError("invalid zone list");
  return `${NWS_ORIGIN}/alerts/active?zone=${ids.join(",")}`;
}

/** Normalises official alerts WITHOUT changing their text. Only alerts whose official UGC
 *  codes intersect the region's codes are kept (no string matching on area names). */
export function normalizeNWS(body: unknown, regionUGC: string[], fetchedAt: string): PublicAlertT[] {
  const coll = NWSCollection.safeParse(body);
  if (!coll.success) throw new UpstreamError("malformed NWS collection");
  const wanted = new Set(regionUGC);
  const out: PublicAlertT[] = [];
  for (const raw of coll.data.features) {
    const f = NWSFeature.safeParse(raw);
    if (!f.success) continue; // skip a malformed feature rather than inventing fields
    const p = f.data.properties;
    if (p.status && p.status !== "Actual") continue; // exercises/tests are never live warnings
    const zones = p.geocode.UGC.filter((z) => UGC.test(z));
    if (!zones.some((z) => wanted.has(z))) continue;
    const sourceURL = f.data.id.startsWith(`${NWS_ORIGIN}/`) ? f.data.id : `${NWS_ORIGIN}/alerts/${encodeURIComponent(p.id)}`;
    out.push({
      id: p.id,
      event: p.event,
      headline: p.headline ?? null,
      description: p.description ?? "",
      instruction: p.instruction ?? null,
      severity: p.severity,
      areaDesc: p.areaDesc,
      affectedZones: zones,
      sent: p.sent,
      effective: p.effective ?? null,
      expires: p.expires ?? null,
      ends: p.ends ?? null,
      fetchedAt,
      sourceURL,
      classification: "live",
    });
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
}

function parseMaxAge(cacheControl: string | null): number {
  const m = cacheControl?.match(/(?:s-)?max-age=(\d+)/);
  const v = m ? Number(m[1]) : 60;
  return Math.min(Math.max(v, 30), 300); // floor protects NWS, ceiling keeps warnings timely
}

export async function fetchNWSAlerts(ugcIDs: string[], deps: NWSDeps): Promise<NWSResult> {
  const url = buildAlertsURL(ugcIDs);
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), deps.timeoutMs);
  let res: Response;
  try {
    res = await deps.fetch(url, {
      headers: { "User-Agent": deps.userAgent, Accept: "application/geo+json" },
      signal: ctrl.signal,
      redirect: "error",
    });
  } catch {
    throw new UpstreamError("NWS unreachable");
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) throw new UpstreamError(`NWS status ${res.status}`);
  const len = Number(res.headers.get("content-length") ?? "0");
  if (len > MAX_NWS_BYTES) throw new UpstreamError("NWS response too large");
  const text = await res.text();
  if (text.length > MAX_NWS_BYTES) throw new UpstreamError("NWS response too large");
  let body: unknown;
  try { body = JSON.parse(text); } catch { throw new UpstreamError("NWS response not JSON"); }
  return { alerts: normalizeNWS(body, ugcIDs, deps.now().toISOString()), maxAgeSeconds: parseMaxAge(res.headers.get("cache-control")) };
}
