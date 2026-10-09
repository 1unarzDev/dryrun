// Locale integrity: translations must preserve placeholders, numbers (incl. phone numbers and units),
// and must be marked draft in the manifest until a qualified reviewer approves them.
import { describe, expect, it } from "vitest";
import bundleJSON from "../src/generated/bundle.json";

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
