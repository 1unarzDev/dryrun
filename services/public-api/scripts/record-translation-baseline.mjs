// Records, for each translated key, a hash of the ENGLISH text it was translated from.
// Run after translating:  node scripts/record-translation-baseline.mjs es vi
//   Adds hashes only for translated keys that have NO baseline yet; existing hashes are kept, so drift
//   on already-translated keys stays visible.
// After re-translating a stale key: node scripts/record-translation-baseline.mjs es vi --accept <domain:key>...
// The drift test (test/locales.test.ts) then fails when English changes under an existing translation.
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const locales = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "content", "locales");
const baselinePath = join(locales, "translation-baseline.json");
const hash = (s) => createHash("sha256").update(s, "utf8").digest("hex").slice(0, 16);
const baseline = existsSync(baselinePath) ? JSON.parse(readFileSync(baselinePath, "utf8")) : { schemaVersion: 1, locales: {} };
const args = process.argv.slice(2);
const acceptAt = args.indexOf("--accept");
const targets = acceptAt === -1 ? args : args.slice(0, acceptAt);
const accepted = new Set(acceptAt === -1 ? [] : args.slice(acceptAt + 1));
if (targets.length === 0) { console.error("usage: record-translation-baseline.mjs <locale>..."); process.exit(1); }
for (const code of targets) {
  const out = {};
  for (const f of readdirSync(join(locales, code)).filter((f) => f.endsWith(".json")).sort()) {
    const domain = f.replace(/\.json$/, "");
    const en = JSON.parse(readFileSync(join(locales, "en", f), "utf8"));
    const tr = JSON.parse(readFileSync(join(locales, code, f), "utf8"));
    const prev = baseline.locales[code]?.[domain] ?? {};
    out[domain] = Object.fromEntries(Object.keys(tr).filter((k) => k in en).sort().map((k) =>
      [k, k in prev && !accepted.has(`${domain}:${k}`) ? prev[k] : hash(en[k])]));
  }
  baseline.locales[code] = out;
}
baseline.note = "Hash (sha256, 16 hex) of the English source each translation was made from. Stale = English changed since.";
writeFileSync(baselinePath, JSON.stringify(baseline, null, 1) + "\n");
console.log(`recorded baseline for ${targets.join(", ")}`);
