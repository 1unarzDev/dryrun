# First review guide

## Try it in five minutes

**On any machine with Docker**, which runs the core logic that actually works today:

```sh
scripts/swift.sh packages/DryRunCore test                  # full core suite
scripts/swift.sh packages/DryRunVault test                 # encrypted vault + public cache
(cd services/public-api && pnpm install && pnpm test)      # public API
DRYRUN_DUMP=1 scripts/swift.sh packages/DryRunCore test --filter PlanDemoDump
```

The last command prints readable rehearsal timelines, decisions, recommendations, before/after comparisons, and a
Vietnamese plan for the fictional households. That is the fastest way to judge the content without the app.

**On a Mac** (Xcode 16.3 or later; verified with Xcode 27 on the iOS 27 simulator):
`scripts/mac/verify.sh` runs everything and writes a bundle. To try the app by hand:
`brew install xcodegen && cd apps/ios && xcodegen && open DryRun.xcodeproj`, then follow the demo in the README.

## Screenshots

None. No simulator or device was available on the Linux build host, so no honest screenshots exist.

## What works (tested on Linux)

- A deterministic rehearsal engine with six distinct scenario packs. Each has at least two decisions and failure and recovery branches, and AND/OR dependencies with backup allocation that never double-counts.
- An evidence chain for every event, typed unknowns, and a lexicographic ranking of recommendations.
- Counterfactual "Try this change" replay. It preserves the baseline and produces a structured diff. For example, confirming the oxygen concentrator's backup removes three critical events and resolves the power requirement.
- Home model, validator, egress planner, scan import, and guided confirmation. Routes use confirmed evidence only, are wall-aware, and are independence-checked. Every scanned element starts as proposed and becomes verified only through an explicit confirmation answer.
- A plan builder with EN/ES/VI output, visible draft and fallback labeling, private notes excluded by default, and stale detection when the home or household changes.
- An encrypted vault (AES-GCM, authenticated header, atomic writes, recovery copies). Locked, key-lost, and corrupt are distinct states.
- A public-data API (no household endpoints, allowlisted region IDs, NWS normalization that drops cancelled alerts) and a curated directory with explicit coverage.

## Highest-priority gaps

1. **No physical-device run yet.** The app builds and passes its UI journeys and screenshot tour on the iOS 27
   simulator. RoomPlan capture, Keychain and file protection, AirPrint, Foundation Models, and iOS 18 are unverified.
2. **No human review** of safety content or translations has happened.
3. **County directory:** only some of the 13 counties have verified emergency-management contacts.
4. **Not deployed:** the public API, and the FEMA flood-map live adapter, which returns a fixture.
5. **No student work yet.** See `AI_ASSISTANCE.md` and `STUDENT_IMPLEMENTATION.md`.

## Questions for the next review

1. **Flagship demo:** is the before/after comparison for the freeze scenario (Oak household, confirming the oxygen concentrator's backup) the cascade you want to lead with? Or should a no-car or renter household lead, to show that preparedness isn't about buying things?
2. **Rehearsal pacing:** a step-through timeline with decision cards, or a home-centric view where the 3D/2D house is the primary canvas and events annotate it?
3. **Content review:** who will review the safety wording, and who will review Spanish and Vietnamese, before the October 26 deadline? Until then, should the demo use English only?
4. **Region scope:** keep the statewide pack plus a few deeply verified counties (Erath, Hood), or spend time verifying OEM contacts for all 13?
5. **Student ownership:** which two items in `STUDENT_IMPLEMENTATION.md` will the student take on, so the AI build can stop touching those areas?
6. **Backend:** authorize deploying the Worker (with an NWS User-Agent contact), or stay bundled-only for the competition demo?
7. **Visual direction:** keep the restrained neutral/teal palette, or provide brand guidance for the design pass?
