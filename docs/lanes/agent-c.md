# Agent C lane report — privacy, public data, locales

AI-authored (Claude, acting as Agent C) on 2026-10-09. Nothing here is student-authored.

## Status

| Item | Status | Evidence |
|---|---|---|
| `packages/DryRunVault` encrypted vault (AES-GCM, authenticated header, atomic write, recovery copy, migrations, delete-all) | TESTED_CORE (Linux, swift-crypto) | `DRYRUN_SCRATCH=c scripts/swift.sh packages/DryRunVault test` → 31 tests, 5 suites, pass |
| `PublicPackStore` known-good public cache | TESTED_CORE | same run |
| `PublicDataPolicy` (alert freshness, activation display, region allowlist, `PublicQueryBuilder`) | TESTED_CORE | `scripts/swift.sh packages/DryRunCore test --filter PublicData` → 11 tests pass |
| Swift ⇄ TS contract fixtures (`content/regions/*.json`, `services/public-api/test/fixtures/contract-alerts.json`) | TESTED_CORE both sides | `PublicDataContractTests` (Swift) + `api.test.ts` (Vitest) |
| `services/public-api` Hono Worker | TESTED_CORE (Node/Vitest), typecheck clean, `wrangler deploy --dry-run` bundles (875 KiB) | `cd services/public-api && pnpm test` → 32 tests pass (api 24 + locales 8); `pnpm typecheck` |
| NWS alerts adapter | IMPLEMENTED + tested against a **recorded** real response (2026-10-09T18:59Z) and synthetic variants; never called live from tests | `test/fixtures/nws-alerts-tx-recorded.json` |
| FEMA NFHL adapter | PARTIAL — interface + labelled `fixture` provider only. Live NFHL lookup **not implemented**; endpoint not verified | `src/fema.ts` |
| Deployment | NOT DONE (not authorised). `wrangler.toml` has no secrets; set a real `NWS_USER_AGENT` contact first | |
| iOS `KeychainVaultKeyStore`, `VaultFileProtection`, `PublicAPIClient` | AUTHORED, `swiftc -parse` only. Not compiled (no iOS SDK). Keychain/data-protection behaviour needs a device | `apps/ios/DryRun/Services/` |
| Locale packs es/vi for `common`, `plan`, `help` | DRAFT translations (AI). Manifest marks them `draft`. Integrity test checks placeholders/numbers/phones | `test/locales.test.ts` |
| es/vi `scenarios` (315 keys), `actions` (76 keys) | DRAFT translations, complete against final English; placeholder sets identical (checked in Vitest and by the lead's `PlanBuilderTests`) | |

## Vault design (what to review)

- File: `u32be headerLen | header JSON | AES.GCM combined(nonce|ct|tag)`. Header (magic, format version, payload
  schema version, key ID, algorithm, createdAt) bytes are the GCM associated data → any metadata edit fails auth.
- Fresh random nonce per seal (library default). Key: random 256-bit, stored by `VaultKeyStore`
  (iOS: Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, non-synchronizable).
- `load()` returns `nil` only for a genuine first launch (no vault file). Locked → `.keyUnavailableWhileLocked`
  (no recovery copy, nothing touched). Vault present but key gone → `.keyLost` and `save()` refuses to mint a new
  key over it. Bad ciphertext/header → `.corrupted(recoveryCopy:)`; original left in place and copied to `recovery/`.
- Migrations are pure `Data → Data` steps; failure throws and writes nothing. A newer-schema vault is refused.
- Atomic write: temp sibling → protect → `rename(2)` → re-protect and **verify** the final path.
- Derived private caches are encrypted and bound to a `RevisionKey`; a different household/home/content/algorithm
  revision is a cache miss. `VaultPayload.pruneStale(current:)` drops stale plans/results.
- Plaintext export (PDF) is the only plaintext private file; lives in `private/exports`, protected, removed by
  `cleanupExports()`/`removeExport`/`deleteAll()`.
- `deleteAll()` removes vault, recovery copies, derived caches, exports, and the key; keeps `public/` packs.
- Recovery consequence (document for users): ThisDeviceOnly key means a new phone cannot open an old vault; there
  is no backup/recovery feature yet (deliberately not faked).

Tested privacy/storage bullets (brief §18): canary absent from all vault/derived/public-cache files and from every
public request URL; tamper (ciphertext and header) fails without destroying; locked ≠ corruption; key loss ≠ empty
onboarding; failed atomic save and failed migration preserve prior data; export is the only plaintext file and
cleanup removes it; delete-all purges derived caches + key and keeps public data. **Not testable on Linux:** real
Keychain lock behaviour, `FileProtectionType.complete` enforcement, backup exclusion, app-switcher snapshots.

## Public data

- `content/sources/sources.json`: S01–S31 from the brief plus S41 (Erath OEM), S42 (Hood OEM), S43 (NWS zones).
  All `needsReview` (no human review).
- `content/regions/tx-statewide.json`: 211 Texas (877-541-7905; Option 1 local services, Option 4 STEAR via 2-1-1),
  STEAR (voluntary, shared with planners/responders, **does not guarantee assistance**), TDEM, USAGov/FEMA
  (presidentially declared areas only; 1-800-621-3362), NWS. Each quoted from the official page fetched 2026-10-09.
- `content/regions/tx-25-counties.json`: all 13 counties with official NWS zone/county UGC IDs fetched from
  `api.weather.gov/zones` on 2026-10-09, `inTX25` all/part per the brief, explicit coverage:
  - Erath (48143) `verifiedPartial`: OEM 254-965-1326, 100 W Washington, Stephenville (county page fetched; mentions CodeRED).
  - Hood (48221) `verifiedPartial`: OEM 817-579-3335, 401 Deputy Larry Miller Dr, Granbury (county page fetched).
    Note: a search summary showed a different coordinator/number; the fetched official page was used.
  - Tarrant (48439) `notStarted`: candidate official OEM pages returned HTTP 404; no number included.
  - Other 10 counties `notStarted`.
  - No shelter, warming, or cooling site is listed anywhere; nothing is marked activated (schema forbids
    `active` without `expiresAt`, and `PublicDataPolicy` requires live/curated source evidence).
- "Verified" here means an automated fetch by an AI agent on 2026-10-09, not a human review.

## Public API

Routes: `/v1/health`, `/v1/manifest`, `/v1/regions/{id}/pack`, `/v1/regions/{id}/alerts`,
`/v1/regions/{id}/flood-context` (fixture), `/v1/content/{version}/{locale}`, `/v1/sources/{id}`.
GET/HEAD only; query strings and bodies rejected; IDs allowlisted; NWS URL built only from curated UGC codes on a
fixed origin with `redirect: "error"`, timeout, 2 MB cap, User-Agent, `max-age` honoured (clamped 30–300 s).
`status != "Actual"` NWS messages dropped. Upstream failure → `503 {status:"unavailable", alerts: []}` — never demo
or stale alerts substituted. Packs are unsigned (manifest says so).

## Locales

- `content/locales/manifest.json` uses the lead's shape. English is marked `draft` too: AI-authored safety text with
  no human safety-content review yet.
- es/vi: all five domains drafted. Kept "6,500 feet", phone numbers, and `Option N` digits identical to
  English (the integrity test compares digit sequences); Vietnamese keeps English terms in parentheses where
  official names matter (e.g. "manufactured home", "tornado warning", "Option 4").
- Translation notes for reviewers: "Dé la vuelta, no se ahogue" mirrors NWS's Spanish "Turn Around Don't Drown"
  wording only approximately — check against NWS Spanish material. Vietnamese heat-stroke wording
  ("say nắng nặng (sốc nhiệt)") needs medical-language review.

## Review fixes applied (docs/lanes/review-privacy.md)

| Finding | Fix | Test |
|---|---|---|
| M1 unreadable file → "locked" | new `VaultError.readFailed`; key store alone decides "locked" | `unreadableFileWithKeyIsNotLocked` (chmod 000) |
| M2 save over unreadable vault | `save(_:overwriteUnreadable:)` opens the existing vault first; corrupt/other-key vault is never replaced unless explicit (and then a recovery copy is kept first). `keyMismatch` now carries a recovery copy | `saveRefusesToOverwriteVaultSealedWithAnotherKey`, `saveRefusesToOverwriteCorruptVaultUnlessExplicit` |
| M3 recovery copy claims / duplicates | copy named by SHA-256 of bytes (one per distinct file); `recoveryCopy: URL?` is nil unless the copy exists | `repeatedLoadsOfCorruptVaultKeepOneRecoveryCopy`, `recoveryCopyIsNotClaimedWhenItCouldNotBeWritten` |
| M4 unprotected export left behind | `AtomicFile.write(removeOnVerificationFailure:)` used for exports | `exportFailingVerificationIsRemoved` |
| M6 wrong-county data | `updatePack/updateAlerts(_:expectedRegionID:)` reject mismatches; cache kept | `alertsForWrongCountyRejectedAndCacheKept` |
| M7 pack cache key | known-good packs keyed by requested region: `knownGoodPack(regionID:)` | `packMustContainRequestedRegionAndIsFoundByRegionOffline` |
| M8 NWS Cancel/Update | drop `messageType == "Cancel"`, drop messages referenced by another message, drop missing/non-`Actual` status | Vitest "drops Cancel messages…" |
| M9 body timeout / streamed cap | single deadline covers fetch + body; body read via reader with running byte count | Vitest "timeout covers a body…", "streamed body … capped by bytes" |
| L1 temp file protection / fsync | Darwin: temp created with `.complete`; `FileHandle.synchronize()` before rename | (device-only for protection class) |
| L2 orphaned temp files | `deleteAll` removes the whole `private/` tree | `deleteAllRemovesOrphanedTempFiles` |
| L3 prefix check | path-component comparison in `removeExport` | `removeExportIgnoresSiblingDirectories` |
| L7 `ends ?? expires` | earlier of `ends` and `expires` | `expiredAlertNeverCurrentEvenIfCached` |

Not mine / not done: H1–H5 (app files), M5 (print/share lifecycle, app), L4–L6/L8/L9 (app).

## Gaps / next

1. FEMA NFHL live lookup (ArcGIS REST) with map date/effective status — not started.
2. Signed manifests (pinned public key) — not started; packs are unsigned and safety rules stay bundled.
3. Remaining 11 counties' OEM/utility/water contacts; Tarrant OEM needs a working official URL.
4. Device tests: Keychain lock (`errSecInteractionNotAllowed`), file protection class, backup exclusion.
5. Human language review for every es/vi string before release.
