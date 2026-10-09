// Bundles PUBLIC repository content (region packs, source manifest, locale packs, content manifest)
// into src/generated/bundle.json for the Worker. No household data exists in these directories.
import { readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "content");
const readJSON = (p) => JSON.parse(readFileSync(p, "utf8"));

const regionsDir = join(root, "regions");
const regionPacks = readdirSync(regionsDir).filter((f) => f.endsWith(".json")).sort().map((f) => readJSON(join(regionsDir, f)));

const locales = {};
const localesDir = join(root, "locales");
for (const code of ["en", "es", "vi"]) {
  const dir = join(localesDir, code);
  locales[code] = {};
  if (!existsSync(dir)) continue;
  for (const f of readdirSync(dir).filter((f) => f.endsWith(".json")).sort()) {
    locales[code][f.replace(/\.json$/, "")] = readJSON(join(dir, f));
  }
}

const contentManifestPath = join(root, "manifest.json");
const bundle = {
  contentManifest: existsSync(contentManifestPath) ? readJSON(contentManifestPath) : { contentVersion: "2026.10.0" },
  localeManifest: existsSync(join(localesDir, "manifest.json")) ? readJSON(join(localesDir, "manifest.json")) : null,
  sources: readJSON(join(root, "sources", "sources.json")),
  regionPacks,
  locales,
};
mkdirSync(join(dirname(fileURLToPath(import.meta.url)), "..", "src", "generated"), { recursive: true });
writeFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "src", "generated", "bundle.json"), JSON.stringify(bundle));
console.log(`bundled ${regionPacks.length} region packs, locales: ${Object.entries(locales).map(([k, v]) => `${k}(${Object.keys(v).length})`).join(" ")}`);
