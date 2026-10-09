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
    references: z.array(z.object({ identifier: z.string() }).passthrough()).optional(),
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
  const features = coll.data.features.map((raw) => NWSFeature.safeParse(raw)).filter((f) => f.success).map((f) => f.data);
  // An Update or Cancel names the messages it replaces; those replaced messages are no longer current.
  const superseded = new Set(features.flatMap((f) => (f.properties.references ?? []).map((r) => r.identifier)));
  const out: PublicAlertT[] = [];
  for (const f of features) {
    const p = f.properties;
    if (p.status !== "Actual") continue; // exercises/tests/drafts (or missing status) are never live warnings
    if (p.messageType === "Cancel") continue; // a cancellation must never display as the warning it cancels
    if (superseded.has(p.id)) continue;
    const zones = p.geocode.UGC.filter((z) => UGC.test(z));
    if (!zones.some((z) => wanted.has(z))) continue;
    const sourceURL = f.id.startsWith(`${NWS_ORIGIN}/`) ? f.id : `${NWS_ORIGIN}/alerts/${encodeURIComponent(p.id)}`;
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

/** Reads the body with a running BYTE count, aborting past `max` without buffering the rest. */
async function readCapped(res: Response, max: number, ctrl: AbortController): Promise<string> {
  if (!res.body) return "";
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      ctrl.abort();
      await reader.cancel().catch(() => {});
      throw new UpstreamError("NWS response too large");
    }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { all.set(c, off); off += c.byteLength; }
  return new TextDecoder().decode(all);
}

function withTimeout<T>(p: Promise<T>, ms: number, ctrl: AbortController): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => { ctrl.abort(); reject(new UpstreamError("NWS timeout")); }, ms);
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
}

export async function fetchNWSAlerts(ugcIDs: string[], deps: NWSDeps): Promise<NWSResult> {
  const url = buildAlertsURL(ugcIDs);
  const ctrl = new AbortController();
  // One deadline covers connection, headers, AND the body read.
  const { text, cacheControl } = await withTimeout((async () => {
    let res: Response;
    try {
      res = await deps.fetch(url, {
        headers: { "User-Agent": deps.userAgent, Accept: "application/geo+json" },
        signal: ctrl.signal,
        redirect: "error",
      });
    } catch {
      throw new UpstreamError("NWS unreachable");
    }
    if (!res.ok) throw new UpstreamError(`NWS status ${res.status}`);
    const len = Number(res.headers.get("content-length") ?? "0");
    if (len > MAX_NWS_BYTES) throw new UpstreamError("NWS response too large");
    try {
      return { text: await readCapped(res, MAX_NWS_BYTES, ctrl), cacheControl: res.headers.get("cache-control") };
    } catch (e) {
      throw e instanceof UpstreamError ? e : new UpstreamError("NWS body read failed");
    }
  })(), deps.timeoutMs, ctrl);
  let body: unknown;
  try { body = JSON.parse(text); } catch { throw new UpstreamError("NWS response not JSON"); }
  return { alerts: normalizeNWS(body, ugcIDs, deps.now().toISOString()), maxAgeSeconds: parseMaxAge(cacheControl) };
}
