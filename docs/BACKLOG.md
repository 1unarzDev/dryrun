# Backlog (priority order)

Each item: acceptance condition · dependencies. "P0" blocks a credible demo; "P1" is needed for the full product;
"P2" improves it.

## P0 — make it run where it must run

1. **Compile and run on macOS / Xcode 26 (iOS 18 deployment target).**
   Accept: `xcodegen && xcodebuild -scheme DryRun -destination 'platform=iOS Simulator,name=<real device name>' build test`
   succeeds; UI journeys in `DryRunUITests` pass; results recorded in VERIFICATION.md. · Depends on: Mac with Xcode.
2. **Device verification of the vault.** Accept: on a physical iPhone, key created with
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; vault file attributes show `NSFileProtectionComplete` and
   excluded-from-backup after atomic replace; locked-device launch shows "Unlock your iPhone", not onboarding.
3. **Human safety-content review** of every string in `content/locales/en` and scenario packs against the cited
   sources; flip manifest review states only after review. · Depends on: a qualified reviewer.
4. **Language review** for ES and VI by fluent reviewers; until then all ES/VI output keeps the draft banner.

## P1 — complete the required product

5. **RoomPlan capture on device.** Accept: single-session multi-room scan on a LiDAR iPhone produces a proposed
   HomeModel with correct relative room placement; confirmation pass required before routes; unsupported devices
   see the manual path. Physical scan results recorded (TESTED_DEVICE). · Depends on: LiDAR iPhone.
6. **Confirmation pass on device.** The guided flow (`HomeConfirmationView` over the tested `HomeConfirmation` logic) is
   built. Accept: after a real scan, every opening is answered or left unknown; routes appear only for confirmed exits.
7. **PDF verification.** Accept: rendered EN/ES/VI PDFs for all sample households have no clipped text, correct
   Vietnamese diacritics, searchable text, and continuation pages reported (never shrunk below 11 pt).
8. **Move remaining hard-coded UI chrome strings into the locale packs / String Catalog** with plural rules;
   test with the longest ES/VI strings and Dynamic Type XXL.
9. **Unify temporary exports on `HouseholdVaultRepository.makeExportFile`** (one protected export location).
10. **Region coverage:** verified OEM contact for each of the 13 TX-25 counties, with check dates; county-level
    alert enrollment links. Partial-county membership must not be asserted without boundary checks.
11. **Deploy the public API** (after authorization): Cloudflare Worker with the NWS User-Agent contact set; client
    base URL configured; app still fully functional offline.
12. **Signed content updates** (pinned public key, manifest with hashes/versions) before any downloadable rule content.
13. **FEMA NFHL live adapter** (map date, effective/preliminary status, missing coverage) — currently fixture only
    unless `docs/lanes/agent-c.md` says otherwise.

14. **Basement walkout and split-level exits:** a per-door "this opens to ground outside" confirmation, replacing the
    level-0 rule.
15. **Same-room exits:** two exits from the start room count as independent. The UI should say "both exits are in
    this room".
16. **Explicit style markers on safety lines** (prohibition/caveat) in content, replacing English keyword detection.
17. **Regional agent:** schedule runs, store claims for human review, and surface reviewed claims in the Help tab.
18. **Helper "assigned" line ordering:** it currently appears before a later "helper blocked" event in the fire timeline.
19. **Vault-backed derived cache:** use `storeDerived`/`loadDerived` for rehearsal results keyed by RevisionKey.

## P2 — quality and reach

20. Design pass (owner-directed): typography, spacing, dollhouse styling, scenario art direction (restrained).
21. Performance on device: measure dollhouse frame pacing and simulation latency on the oldest supported iPhone.
22. Accessibility audit with VoiceOver, Switch Control, Reduce Motion/Transparency, contrast checks.
23. Optional on-device explanations: evaluate prose quality and validator false-accept rate on iOS 26 hardware.
24. Encrypted, user-controlled export/recovery-key design (no server-held keys).
25. Additional scenario variants (night fire, apartment common-stair fire, multi-day heat with intermittent grid).
