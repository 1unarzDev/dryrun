// Deterministic extraction of checkable facts. No model involved; every value is a verbatim substring.
import { createHash } from "node:crypto";
import type { ClaimType, FetchedSource, PublicClaim } from "./types";
import { isPublicHTTPSURL } from "./publicURL";

export const PHONE_RE = /^(?:1[-. ])?(?:\(\d{3}\) ?|\d{3}[-.])\d{3}[-.]\d{4}$/;
export const DATE_RE = /^(?:\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?)?|(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}|\d{1,2}\/\d{1,2}\/\d{4})$/;

const PATTERNS: Array<[ClaimType, RegExp]> = [
  // US numbers: 877-541-7905, (817) 598-0969, 1-800-621-3362, 940.567.2259
  ["phone", /(?<![\d-])(?:1[-. ])?(?:\(\d{3}\) ?|\d{3}[-.])\d{3}[-.]\d{4}(?![\d-])/g],
  ["url", /https:\/\/[A-Za-z0-9.-]+(?:\/[^\s"'<>)\]]*)?/g],
  ["date", /\b(?:\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:\d{2})?)?|(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}|\d{1,2}\/\d{1,2}\/\d{4})\b/g],
  ["ugc", /\b[A-Z]{2}[CZ]\d{3}\b/g],
];

export const claimID = (sourceID: string, type: ClaimType, value: string) =>
  `${sourceID}:${type}:${createHash("sha256").update(value).digest("hex").slice(0, 12)}`;

export function extractClaims(src: FetchedSource, context: { regionID: string | null; jurisdiction: string | null }): PublicClaim[] {
  const out = new Map<string, PublicClaim>();
  for (const [claimType, re] of PATTERNS) {
    for (const m of src.text.matchAll(re)) {
      const value = m[0].replace(/[.,;:]+$/, "");
      if (claimType === "url" && !isPublicHTTPSURL(value)) continue; // no internal/IP/odd-port links
      const id = claimID(src.sourceID, claimType, value);
      if (out.has(id)) continue;
      out.set(id, { id, claimType, value, sourceID: src.sourceID, regionID: context.regionID, jurisdiction: context.jurisdiction,
                    retrievedAt: src.retrievedAt, uncertainty: "verbatimExtracted", reviewState: "needsReview", generatedBy: "deterministic" });
    }
  }
  return [...out.values()].sort((a, b) => a.id.localeCompare(b.id));
}
