# Dry Run public API (Cloudflare Worker)

Public information only. There are no household/home endpoints; only `GET`/`HEAD`; any query string or request
body is rejected; region, locale, version, and source IDs are allowlisted. The app works fully without this service.

| Route | Purpose |
|---|---|
| `GET /v1/health` | liveness + content version |
| `GET /v1/manifest` | pack versions, freshness, locale review manifest (unsigned) |
| `GET /v1/regions/{regionID}/pack` | region-scoped curated resources (bundled from `content/regions`) |
| `GET /v1/regions/{regionID}/alerts` | NWS active alerts for the region's official UGC codes; `503 unavailable` on upstream failure |
| `GET /v1/regions/{regionID}/flood-context` | FEMA NFHL context — **fixture only; live lookup not implemented** |
| `GET /v1/regions/{regionID}/brief` | deterministic template brief (pack + cached alerts + flood adapter); no model |
| `GET /v1/content/{version}/{locale}` | locale packs (`en`/`es`/`vi`) with review state |
| `GET /v1/sources/{sourceID}` | one source record (`S01`…) |

```sh
pnpm install          # lockfile pinned; esbuild/workerd build scripts allowed in pnpm-workspace.yaml
pnpm test             # bundles content/, then Vitest
pnpm typecheck
pnpm dev              # local wrangler dev server
```

Deployment has **not** been performed. Before `pnpm deploy`: set `NWS_USER_AGENT` in `wrangler.toml` to a real
contact (NWS requirement), and review the region packs. Content is unsigned; safety rule content stays bundled in
the app and only validated public data is downloadable until a signing design is reviewed.

Caching: per-isolate TTL cache honouring NWS `max-age` (clamped 30–300 s). The service does not log request details.
Note: infrastructure providers still see network metadata (IP, selected region path).

`src/agent/` holds the public-only regional agent (allowlisted source fetch, deterministic claim extraction, optional
model boundary defaulting to `UnavailableProvider`). See `docs/lanes/agent-c.md`.

After translating: `node scripts/record-translation-baseline.mjs es vi` (adds new keys only).
