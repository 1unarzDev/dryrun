# Wired-iPhone pass — October 20, 2026 (Claude on the Mac)

Branch `dryrun-six-hazard-continue` (Linux six-hazard work merged with `main` f9b296c; see the integration note at the
top of [scenario-experience-handoff.md](scenario-experience-handoff.md)). Device: iPhone 16 Pro, USB, owner's Personal
Team. All households, homes and Gemini traffic are the fictional demo data (`synthetic: true`).

Evidence categories as in [the 10-19 pass](wired-iphone-pass-2026-10-19.md): **phone**, **Mac**, **live synthetic**,
**pending**. "Passed" means the named test or journey ran; it is not a safety claim.

## Driving the phone

`scripts/mac/device-test.sh [<-only-testing target>…]` builds, signs (same team/bundle as `device.sh`), runs the
selected tests on the connected iPhone and exports every screenshot attachment to
`.build-mac/device-tests/<run>/attachments`. Live-gateway journeys read `TEST_RUNNER_AIGATEWAY` /
`TEST_RUNNER_AIGATEWAYTOKEN`; the gateway runs with `DRYRUN_HOST=<Mac LAN address>`.

## What changed

| Area | Change | Evidence |
|---|---|---|
| Prepare order | Within a priority tier the Prepare list now puts life-sustaining medical dependencies first (powered/refrigerated equipment, essential medication), then life safety (helper, alarms, exits, shelter), then effort/breadth/ID. Never across tiers. Per-rehearsal recommendation order is unchanged (frozen fixtures and the 24 legacy result hashes still match). | Mac (`RankingTests`, all three sample households) |
| Prepare speed | The six Prepare rehearsals run concurrently (order preserved); the merged summary is memoized on its inputs and the day instead of recomputed on every view access. | phone (unit + journeys) |
| Gemini preparation | `PreparationFeatureBridge` (Core) builds the `/v1/features` `preparation` request with the same constructors as `DryRunHost`, accepts only tasks that exactly name an item on this household's to-do list (ID + action + subject), reorders within tiers only, keeps bespoke ideas separate and unscored, and rewrites internal record IDs to the household's own labels. Prepare shows an explicit-tap "Personalize with Gemini" card (fictional households, dev gateway), Gemini's reason under each accepted item, a refused-suggestion count, its question, and "Use the app's order". The gateway prompt now forbids internal IDs in family-facing text. | Mac (Swift→Zod contract for all three households; recorded live answer); **phone, live synthetic: passed** |
| Native bridge | `validateSuggestedActions` executes through Core and returns only `{id, feasible, rejection}`. App tool loop 6. | Mac, phone (adaptive fire) |
| Accessibility | Setup, debrief-hazard and debrief-outcome containers no longer overwrite their children's identifiers (VoiceOver/automation could not address setup options). | phone |
| Floor plan | Room names wrap between words only; tall narrow rooms (shared corridor/stair landing, bathroom) draw their name vertically instead of "Share d corri- dor". | phone screenshot |
| Units | Scene and debrief quantities use the household's country (US → gallons). Demo households with no recorded country stay metric, as on Prepare. | phone |
| Marker journey | Updated for the tap/room-picker marker editor (no typed coordinates); moved marker needs location review. | phone |

## Phone runs (final build)

| Suite | Result |
|---|---|
| DryRunTests (app unit, incl. encrypted vault, adaptive resume, persistence) | all passed |
| SixHazardUITests — each hazard via normal navigation: setup, a non-default setup answer, decisions, run to the end, debrief with outcome evidence | 6 / 6 passed |
| DeviceAuditUITests (adaptive fire/water, every floor 2D/3D, scorecard ×4, supply intake, marker relocation, practice check, large text) | passed (marker journey after its update) |
| Gemini preparation journey (live) | passed: Oak's oxygen-concentrator backup led with a household-specific reason; reset restored the app's order |
| Gemini director journey (live) | **not shown**: Google returned 503 "high demand" for gemini-3.1-flash-lite and gemini-3.8-flash, then the gateway's DRYRUN_MAX_USD cap stopped further calls. The app fell back to the on-device director and said so. Retry when the provider is available. |

## Remaining

- Live Gemini director on the phone (provider overload today); fresh all-six live quality.
- ES/VI wording of the new Prepare strings is a draft needing human review (baseline recorded with the new
  `scripts/record-translation-baseline.mjs`, which only adds missing entries).
- Gemini's free text is English regardless of app language.
- Production authorization (App Attest) before any real household can use either Gemini feature.
