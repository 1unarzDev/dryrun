// The agent's ONLY network tool. It takes a source ID (never a URL), resolves it through the curated
// source manifest, and fetches with: https only, host allowlist, manual redirect handling restricted to the
// same host, one deadline covering headers + body, a byte cap, and text-only extraction.
import type { FetchedSource } from "./types";

export const MAX_SOURCE_BYTES = 1_500_000;
export const MAX_TEXT_CHARS = 200_000;
const SOURCE_ID = /^S\d{2,3}$/;

export interface SourceRecord { id: string; url: string }
export interface FetchDeps { fetch: typeof fetch; userAgent: string; timeoutMs: number; now: () => Date }

export class SourceFetchError extends Error {}

export class SourceAllowlist {
  private byID = new Map<string, URL>();
  readonly hosts = new Set<string>();
  constructor(sources: SourceRecord[]) {
    for (const s of sources) {
      let u: URL;
      try { u = new URL(s.url); } catch { continue; }
      if (u.protocol !== "https:" || u.username || u.password || u.port) continue;
      this.byID.set(s.id, u);
      this.hosts.add(u.hostname);
    }
  }
  resolve(sourceID: string): URL {
    if (typeof sourceID !== "string" || !SOURCE_ID.test(sourceID)) throw new SourceFetchError("invalid source ID");
    const u = this.byID.get(sourceID);
    if (!u) throw new SourceFetchError("source ID not in allowlist");
    return new URL(u.href);
  }
}

/** Strips markup to plain text. Scripts, styles, comments, and attributes are discarded. */
export function htmlToText(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<(script|style|noscript|template|svg)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|div|li|h[1-6]|tr)>/gi, "\n")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => { const c = Number(n); return c > 0 && c < 0x110000 ? String.fromCodePoint(c) : " "; })
    .replace(/[ \t\f\r\v]+/g, " ").replace(/\n\s*\n+/g, "\n").trim();
}

async function readCapped(res: Response, max: number): Promise<string> {
  if (!res.body) return "";
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) { await reader.cancel().catch(() => {}); throw new SourceFetchError("response too large"); }
    chunks.push(value);
  }
  const all = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { all.set(c, off); off += c.byteLength; }
  return new TextDecoder().decode(all);
}

export async function fetchOfficialSource(sourceID: string, allow: SourceAllowlist, deps: FetchDeps): Promise<FetchedSource> {
  let url = allow.resolve(sourceID);
  const originHost = url.hostname;
  const ctrl = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => { ctrl.abort(); reject(new SourceFetchError("timeout")); }, deps.timeoutMs);
  });
  const work = (async () => {
    for (let hop = 0; hop <= 2; hop++) {
      if (url.protocol !== "https:" || !allow.hosts.has(url.hostname) || url.hostname !== originHost) {
        throw new SourceFetchError("redirect or URL outside allowlist");
      }
      let res: Response;
      try {
        res = await deps.fetch(url.href, {
          headers: { "User-Agent": deps.userAgent, Accept: "text/html,text/plain" },
          redirect: "manual", signal: ctrl.signal,
        });
      } catch { throw new SourceFetchError("unreachable"); }
      if (res.status >= 300 && res.status < 400) {
        const loc = res.headers.get("location");
        if (!loc) throw new SourceFetchError("redirect without location");
        url = new URL(loc, url);
        continue;
      }
      if (!res.ok) throw new SourceFetchError(`status ${res.status}`);
      const type = res.headers.get("content-type") ?? "";
      if (!/^text\/(html|plain)/i.test(type)) throw new SourceFetchError("not a text page");
      const len = Number(res.headers.get("content-length") ?? "0");
      if (len > MAX_SOURCE_BYTES) throw new SourceFetchError("response too large");
      const raw = await readCapped(res, MAX_SOURCE_BYTES);
      const full = /html/i.test(type) ? htmlToText(raw) : raw;
      return { sourceID, url: url.href, retrievedAt: deps.now().toISOString(),
               text: full.slice(0, MAX_TEXT_CHARS), truncated: full.length > MAX_TEXT_CHARS };
    }
    throw new SourceFetchError("too many redirects");
  })();
  try { return await Promise.race([work, deadline]); } finally { clearTimeout(timer); }
}
