# Adversarial privacy / storage review (Agent B, ~25 min)

Reviewer: Agent B (AI). Read-only review of code written by Agent C and the lead. No reviewed file was edited.
Method: source reading plus cross-checking call sites (grep). Nothing below was verified by running iOS code, because there is no SDK
on this host. Linux-testable proposals are marked so they can become real failing tests.

Severity: **HIGH** means a build blocker on the privacy path, or private data / safety status shown or kept wrongly.
**MEDIUM** means a real defect under plausible conditions. **LOW** means hardening.

## HIGH

**H1 — Vault bridge does not compile; the fix could silently drop file protection.**
`apps/ios/DryRun/Services/VaultPrivateDataStore.swift:15` calls `IOSFileProtection()`, but the type that exists is
`VaultFileProtection` (`apps/ios/DryRun/Services/VaultFileProtection.swift:9`).
- Failure: the app target fails to build. A hurried fix such as a no-op `FileProtectionApplying` would also pass
  `AtomicFile`'s final-file check, because a no-op can report `true`.
- Fix: use `VaultFileProtection()` and `VaultLocations.appDefault()`, which already exists and creates the directory.
  Add a DEBUG assertion that `isProtected` is true on device after the first save.

**H2 — The Help alerts call targets an API that does not exist, and it bypasses the known-good cache.**
`apps/ios/DryRun/Help/HelpViews.swift:174` calls `PublicAPIClient.shared.alerts(regionID:)`. Neither `shared` nor
`alerts(regionID:)` exists; the client only offers `refreshAlerts(regionID:)`.
- Failure: build error. Even after renaming the call, a `throw`-based call path never reaches `PublicPackStore.cachedAlerts`.
  That means no dated offline context is shown, which the brief requires.
- Fix: create one `PublicAPIClient(baseURL:store: PublicPackStore(directory: locations.publicCache))` and inject it.
  Use the `(envelope, freshness)` tuple and display `freshness` (updated / cached at X / unavailable).

**H3 — Offline, the UI says "No current alerts" while a still-valid alert is cached.**
`HelpViews.swift:156-158` filters to `currentOfficialAlerts`. An alert within its validity window but fetched more than 30 minutes ago
(`.stale`, the normal offline case) or with unparseable times (`.unknown`) is dropped. The UI then prints
"No current alerts in the last update (…)".
- Failure: a cached Tornado Warning, fetched 40 minutes ago with `expires` 2 hours out and the phone now offline, reads as an all-clear.
- Fix: partition by `PublicDataPolicy.freshness`. If any alert is `.stale` or `.unknown`, show "An official alert was in effect at
  <fetchedAt>. Current status unavailable" with the dated alert, never styled as current. Say "No current alerts" only when the
  envelope is fresh and holds no unexpired alerts.

**H4 — The app-switcher cover does not cover sheets.**
`apps/ios/DryRun/App/DryRunApp.swift:20` overlays `PrivacyCover` on `RootView`. These are all presented above that overlay, so the
app-switcher snapshot can show their contents:
- `PDFPreviewSheet` (the full plan, with names, phone numbers, and optional care-plan notes)
- `SettingsView`
- `ManualHomeEditorView`
- the household editor
- `RoomScanFlowView` (a full-screen cover)
- Failure: open the plan preview, then swipe to the app switcher. The snapshot shows the plan.
- Fix: present the cover in a dedicated `UIWindow` (`windowLevel = .alert + 1`) on `sceneWillResignActive` / `scenePhase != .active`,
  or apply the same overlay modifier at the root of every sheet and cover. Device check: screenshot the app switcher with each
  modal open.

## MEDIUM

**M1 — An unreadable vault file is reported as "locked".**
`packages/DryRunVault/Sources/DryRunVault/HouseholdVaultRepository.swift:52-54`: `fm.contents == nil` maps to
`.keyUnavailableWhileLocked` even though `keyStore.loadKey()` just succeeded. The key is `WhenUnlocked`, so the device is unlocked.
- Failure: permissions or I/O errors, or a container migration, leave the user on "Unlock your iPhone / Try again" forever.
- Fix: add `VaultError.readFailed(String)` and map it to `.needsRecovery`. Locked has already been detected by the key store.
- Test (Linux): `chmod 000` the vault file with the key available. Expect not `.keyUnavailableWhileLocked`. (Skip when running as root.)

**M2 — `save()` will overwrite a vault it could not open.**
`HouseholdVaultRepository.swift:61-73` never checks what it is replacing. Current safety rests entirely on UI gating
(`VaultRecoveryView` offers only retry or delete).
- `keyMismatch` (`open` line 194) throws before `fail()`, so no recovery copy is made.
- Failure: any future path that persists while in `.vaultNeedsRecovery`, for example a background task or a "use sample household"
  button added to the recovery screen, replaces the only copy of a `keyMismatch` vault or loses an unrecovered corrupt one.
- Fix: in `save`, if a vault exists and its header `keyID` differs from the current key, or the last `load` failed, throw unless
  called with `overwriteUnreadable: true` (used only by explicit delete/start-over). Also copy to recovery on `keyMismatch`.
- Test (Linux): write a vault with key A, swap the key store to key B, call `save(...)`. Expect a throw and an unchanged file.

**M3 — Recovery copy is claimed but may not exist, and copies pile up.**
`HouseholdVaultRepository.swift:223`: `try? AtomicFile.write(...)` ignores failure but still returns the URL.
`VaultPrivateDataStore.swift:30-31` then tells the user "A recovery copy was kept". Each "Try again" on a corrupt vault writes
another copy.
- Fix: return `URL?` only after a successful write, and name the copy by content hash so retries reuse it. The original stays in place
  regardless, so say "the original file was kept".
- Tests (Linux): make `recoveryDir` a regular file and call `load()`. The error's URL must not be claimed unless
  `fileExists(recoveryCopy)`. Separately, call `load()` 3× on the same corrupt file and expect exactly 1 recovery file.

**M4 — Failed protection verification leaves a plaintext export behind.**
`AtomicFile.swift:351-355`: if verification fails, the file was already renamed into place but the caller gets an error.
For `makeExportFile` (`HouseholdVaultRepository.swift:106-111`), that is an unprotected plaintext PDF in `exportsDir` with no URL handed
back to clean up. For `save` it means data was written but an error was shown.
- Fix: give `AtomicFile.write` a `removeOnVerificationFailure` flag, set true for exports. Test with
  `RecordingFileProtection.forget` after rename (needs a hook) or a `FileProtectionApplying` double whose `isProtected` returns false.

**M5 — Purge on background can delete a PDF mid-print or mid-share.**
`DryRunApp.swift:23` purges exports on `.background`, while `PlanViews.swift:148/170` hands a file URL to
`UIPrintInteractionController` / `ShareLink`. Spooling to a printer, or AirDrop continuing after the user switches apps, loses the file.
- Fix: print from `Data` (`printingItem = data`). Keep the export until the share/print completion handler, wrapped in
  `beginBackgroundTask`, then delete it. Keep purge-on-launch as the backstop.

**M6 — Alerts and packs for the wrong county are accepted.**
`PublicPackStore.swift:43-51` validates `env.regionID` format but not that it equals the region requested.
`PublicAPIClient.refreshAlerts` returns whatever arrived.
- Failure: a server or CDN mix-up shows county X's warnings under county Y's heading.
- Fix: pass the expected `regionID` into `updateAlerts` and `updatePack`, and reject a mismatch (for packs, `regions` must contain it).
- Test (Linux): `updateAlerts(envelope for 48221, expected: 48143)` must throw and keep the previous cache.

**M7 — The offline pack fallback depends on a pack ID the caller cannot know.**
The server returns `packID = "<base>.<regionID>"` (`services/public-api/src/app.ts:231`). The client stores packs by that ID
(`PublicPackStore.swift:24,33`), and `refreshRegionPack(regionID:cachedPackID:)` (`PublicAPIClient.swift:43-54`) needs the
derived ID. A caller passing the region or base pack ID gets `.unavailable` offline although a cached copy exists.
- Fix: key the known-good cache by `regionID` (`knownGoodPack(regionID:)`).

**M8 — NWS cancellation messages become live warnings.**
`services/public-api/src/nws.ts:355` filters `status !== "Actual"` but not `messageType == "Cancel"`. A cancellation of a Tornado
Warning is normalised with `event: "Tornado Warning"` and `classification: "live"`, so the app shows it as a current warning.
- Fix: drop `Cancel` messages, or carry `messageType` and show "cancelled". Vitest: a fixture feature with `messageType: "Cancel"`
  must not appear in `alerts`.

**M9 — The NWS fetch has no timeout on the body and no byte cap on streamed responses.**
`nws.ts:399` clears the abort timer in `finally` once headers arrive, so `res.text()` (line 405) can stall until the Worker limit.
A chunked body without `content-length` is fully buffered before the length check, and `text.length` counts UTF-16 units, not bytes.
- Fix: clear the timer after the body is read. Read via `res.body.getReader()` with a running byte count and abort past `MAX_NWS_BYTES`.
- Vitest: a mocked `fetch` whose body never resolves must reject within `timeoutMs`. A 3 MB chunked body with no `content-length`
  must reject without a full buffer.

## LOW

- **L1** `AtomicFile.swift:340`: the temp file is created with default protection, then protected, so ciphertext briefly sits in the
  default class; there is no `fsync` before `rename`. Fix: create it with `attributes: [.protectionKey: .complete]`, or write via
  `Data.write(to: temp, options: .completeFileProtection)`, then `fsync`.
- **L2** `HouseholdVaultRepository.swift:129`: delete-all enumerates known paths, so crash-orphaned `.household.vault.<uuid>.tmp`
  siblings survive. They are ciphertext, and the key is deleted, but still residue. Fix: remove `privateRoot` entirely
  (`publicCache` is a sibling, so it is unaffected).
- **L3** `HouseholdVaultRepository.swift:114`: the `hasPrefix` path check lacks a trailing `/`, so a sibling such as `exports-x/…`
  passes. Compare path components instead.
- **L4** There are two export mechanisms: the repository's `exportsDir`, which the app never uses, and the app's `TemporaryExports` in
  `tmp/`. Delete-all covers both today. Consolidate to one so a future change cannot miss either.
- **L5** `VaultPrivateDataStore.swift:20-22`: a vault that decrypts but has `household == nil || home == nil` maps to `.empty`, which
  leads to onboarding and the next save overwrites it. It should be `.needsRecovery`, because a file existed.
- **L6** Keychain items survive app deletion on iOS, leaving an orphaned key after reinstall. It is harmless because no data remains,
  but document it. Optionally delete a stray key when no vault exists at first launch.
- **L7** `PublicDataPolicy.swift:38`: uses `ends ?? expires`. When `ends > expires`, a message counts as current after it expired.
  Bounded by the 30-minute staleness window and the server's active feed. Suggest `min(expires, ends)`.
- **L8** On the simulator, `VaultFileProtection.isProtected` may not report `.complete`, so every save would error after writing.
  Verify; UI tests already use the in-memory store.
- **L9 (info)** The `ExplanationService` prompt is the template text only: on-device, not logged, no network. Confirm the templates
  never include `carePlanNotes` or phone numbers. `lastError = String(describing:)` puts file paths and key UUIDs on screen, not in
  logs.

## Verified OK (as read)

**Vault**
- Fresh random nonce per seal (`AES.GCM.seal` default).
- The full header bytes are the AAD, so metadata tampering fails authentication.
- A 256-bit random key in the Keychain with `WhenUnlockedThisDeviceOnly` and non-synchronizable.
- Locked, key-lost, and corrupt are distinct states; key loss never mints a new key over an existing vault.
- A failed migration writes nothing.
- The newer-version path refuses rather than overwrites.
- Delete-all keeps the public cache.

**App**
- `.vaultNeedsRecovery` never falls through to onboarding.
- The PDF uses `.completeFileProtection` plus backup exclusion and is purged on dismiss, background, and delete-all.
- No `UserDefaults`, `print`, `os_log`, or pasteboard use in the reviewed app or vault code.
- The public client uses an ephemeral session with no URL cache and no cookies.

**Requests and alerts**
- Requests come only from `PublicQueryBuilder` with allowlisted region, locale, and source tokens. No query items. A canary test exists.
- The server rejects non-GET/HEAD methods, any query string, and any body (`content-length`/`transfer-encoding`).
- Unknown regions return 404. There is no household endpoint.
- The NWS URL uses a fixed origin, regex-validated UGC codes, and `redirect: "error"`.
- Demo, fixture, and curated alerts are never `.current`.
- An activated site requires source evidence plus an expiry.

## Suggested order

1. H1 and H2 (build).
2. H3 and H4 (user-visible safety/privacy).
3. M2, M1, and M3 together (vault overwrite safety).
4. M8 and M6 (alert correctness).
5. M5 and M7. Then the LOW items.
