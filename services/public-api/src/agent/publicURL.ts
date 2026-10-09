// One public-URL rule for the whole agent: allowlist entries, redirect hops, extracted URLs, model URLs.
const RESERVED_SUFFIXES = [".localhost", ".local", ".internal", ".lan", ".home.arpa", ".corp", ".intranet"];

/** Hostname with any trailing dot removed, lower-cased. */
export const normHost = (h: string) => h.toLowerCase().replace(/\.+$/, "");

export function isPublicHostname(hostname: string): boolean {
  const h = normHost(hostname);
  if (!h || h.includes(":") || h.startsWith("[")) return false;           // IPv6 literal
  if (/^[\d.]+$/.test(h) || /^0x/i.test(h)) return false;                 // IPv4 literal (incl. short/hex forms)
  if (!h.includes(".")) return false;                                     // single-label (localhost, intranet names)
  if (h === "localhost" || RESERVED_SUFFIXES.some((s) => h.endsWith(s))) return false;
  return /^[a-z0-9.-]+$/.test(h);
}

/** https, default port, no userinfo, public hostname. */
export function isPublicHTTPSURL(u: URL | string): boolean {
  let url: URL;
  try { url = typeof u === "string" ? new URL(u) : u; } catch { return false; }
  return url.protocol === "https:" && url.port === "" && !url.username && !url.password && isPublicHostname(url.hostname);
}
