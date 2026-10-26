// Locale integrity: translations must preserve placeholders, numbers (incl. phone numbers and units),
// and must be marked draft in the manifest until a qualified reviewer approves them.
import { describe, expect, it } from "vitest";
import bundleJSON from "../src/generated/bundle.json";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

type Domains = Record<string, Record<string, string>>;
const bundle = bundleJSON as unknown as { locales: Record<string, Domains>; localeManifest: any };
const en = bundle.locales.en;

const placeholders = (s: string) => [...s.matchAll(/\{[A-Za-z0-9_]+\}/g)].map((m) => m[0]).sort();
const numbers = (s: string) => [...s.matchAll(/\d[\d,.\-]*\d|\d/g)].map((m) => m[0]).sort();

describe.each(["es", "vi"])("locale %s", (code) => {
  const loc = bundle.locales[code] ?? {};
  const manifest = bundle.localeManifest.locales.find((l: any) => l.code === code);

  it("every translated domain is marked draft (never reviewed by tests alone)", () => {
    for (const domain of Object.keys(loc)) expect(manifest.domains[domain]).toBe("draft");
    for (const [domain, state] of Object.entries(manifest.domains)) {
      if (!(domain in loc)) expect(state).toBe("missing");
    }
  });

  it("has no keys that do not exist in English", () => {
    for (const [domain, strings] of Object.entries(loc)) {
      for (const key of Object.keys(strings)) expect(en[domain]?.[key], `${code}:${key}`).toBeDefined();
    }
  });

  it("preserves placeholders, numbers, units, and phone numbers", () => {
    for (const [domain, strings] of Object.entries(loc)) {
      for (const [key, text] of Object.entries(strings)) {
        const source = en[domain][key];
        expect(placeholders(text), `${code}:${key}`).toEqual(placeholders(source));
        expect(numbers(text), `${code}:${key}`).toEqual(numbers(source));
      }
    }
  });

  it("keeps critical prohibitions present", () => {
    const plan = loc.plan ?? {};
    if (!plan["plan.scenario.water-outage.immediate.3"]) return;
    // Do-not-drink must never turn into a boil instruction: the sentence must keep a negation.
    const neg = code === "es" ? /no la hierva/ : /không đun sôi/;
    expect(plan["plan.scenario.water-outage.immediate.3"]).toMatch(neg);
  });
});

// Drift guard: a translation is stale when the English it was made from has changed since.
// Fix by re-translating the listed keys, then: node scripts/record-translation-baseline.mjs es vi
describe("translation drift against recorded English baseline", () => {
  const baseline = JSON.parse(readFileSync(new URL("../../../content/locales/translation-baseline.json", import.meta.url), "utf8"));
  const hash = (s: string) => createHash("sha256").update(s, "utf8").digest("hex").slice(0, 16);

  it.each(["es", "vi"])("%s: every translated key has a baseline and its English is unchanged", (code) => {
    const stale: string[] = [];
    for (const [domain, strings] of Object.entries(bundle.locales[code] ?? {})) {
      for (const key of Object.keys(strings)) {
        const recorded = baseline.locales?.[code]?.[domain]?.[key];
        if (recorded === undefined) stale.push(`${domain}:${key} (no baseline)`);
        else if (recorded !== hash(en[domain][key])) stale.push(`${domain}:${key} (English changed)`);
      }
    }
    expect(stale).toEqual([]);
  });

  it("detects a changed English string", () => {
    const [domain, strings] = Object.entries(bundle.locales.es)[0];
    const key = Object.keys(strings)[0];
    expect(baseline.locales.es[domain][key]).not.toBe(hash(en[domain][key] + " (edited)"));
  });
});
