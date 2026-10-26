#!/usr/bin/env node
// Records the English source hash for translated keys that have no baseline yet (services/public-api/test/locales.test.ts).
// Usage: node scripts/record-translation-baseline.mjs es vi
// Existing entries are never rewritten: a key whose English changed must be re-translated, then its entry deleted
// from content/locales/translation-baseline.json and recorded again by this script.
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, writeFileSync } from "node:fs";

const root = new URL("../content/locales/", import.meta.url);
const hash = (s) => createHash("sha256").update(s, "utf8").digest("hex").slice(0, 16);
const read = (path) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const baselinePath = new URL("translation-baseline.json", root);
const baseline = JSON.parse(readFileSync(baselinePath, "utf8"));
const codes = process.argv.slice(2);
if (codes.length === 0) { console.error("usage: record-translation-baseline.mjs <locale>…"); process.exit(2); }

let added = 0;
for (const code of codes) {
  for (const file of readdirSync(new URL(`${code}/`, root)).filter((f) => f.endsWith(".json"))) {
    const domain = file.slice(0, -5);
    const translated = read(`${code}/${file}`), english = read(`en/${file}`);
    const recorded = ((baseline.locales[code] ??= {})[domain] ??= {});
    for (const key of Object.keys(translated)) {
      if (recorded[key] !== undefined || english[key] === undefined) continue;
      recorded[key] = hash(english[key]);
      added++;
    }
    baseline.locales[code][domain] = Object.fromEntries(Object.entries(recorded).sort(([a], [b]) => a.localeCompare(b)));
  }
}
writeFileSync(baselinePath, JSON.stringify(baseline, null, 1) + "\n");
console.log(`recorded ${added} new baseline entries`);
