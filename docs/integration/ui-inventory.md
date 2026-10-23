# Native surface and state inventory

Owner: native UI lead, branch `lead/native-ui` (base `cdb4098`). Every reachable screen, sheet and material state,
with the UI test that drives it. **No entry below is verified on a device yet.** The status column records what has
been observed; it is a verification queue, not a pass claim.

## How to capture

`apps/ios/DryRunUITests/UIInventoryUITests.swift` drives every row whose ID it lists, asserts the identifiers that
prove the state was reached, and attaches one full-screen capture named `<ID>-<size>-<locale>`:

- `testInventoryOrdinaryText` (size `std`) and `testInventoryAccessibilityText` (size `axxxl`, AccessibilityXXL).
- Filters: `TEST_RUNNER_INVENTORY_IDS=PREP,CARD-01` (prefix match), `TEST_RUNNER_INVENTORY_LOCALE=en|es|vi`
  (household: en hh-oak, es hh-pine, vi hh-lake).
- Fictional in-memory households only (`-uiTestingInMemory`, `-demoHousehold`). Beacon is disabled
  (`-noBeaconConfig`, `-noSavedBeacon`), so captures carry deterministic app text by construction; the phone
  reviewer still handles them under the output firewall (reference §12). Beacon-bearing states are listed separately
  below and are driven only by reviewer-owned tests.

Example (phone reviewer, device reservation holder):

```
xcodebuild test-without-building -project apps/ios/DryRun.xcodeproj -scheme DryRun \
  -destination 'id=<iPhone UDID>' -derivedDataPath <dir> \
  -only-testing:DryRunUITests/UIInventoryUITests TEST_RUNNER_INVENTORY_LOCALE=en
```

Status values: `unverified` (no capture yet), `blocked` (cannot be driven by an in-memory fixture; reason given),
`captured` (capture exists, no layout verdict), `pass`/`fail` (reviewer verdict with report reference).

## Inventory

| ID | Surface / state | Source | How it is reached | Asserted identifiers | Status |
|---|---|---|---|---|---|
| ONB-01 | Onboarding, no household | `Home/HouseholdSetupView.swift` (OnboardingView) | launch, no household | `onboarding.demo` | unverified |
| ONB-02 | Onboarding, more examples expanded | same | tap `onboarding.moreExamples` | `onboarding.sample.*` | unverified |
| ONB-03 | Household setup, first step | `Home/HouseholdSetupView.swift` | tap `onboarding.create` | `setup.next` | unverified |
| ONB-04 | Setup people step (labelled Name, capitalized needs) | same | setup steps | — | unverified; not driven by the inventory test (requires stepping through setup) |
| ONB-05 | Describe household (intake review sheet) | `Home/DescribeHouseholdView.swift` | onboarding describe path | — | unverified; `DemoJourneyUITests.testDescribeHouseholdReviewThenTarrantCountyHelp` |
| ROOT-01 | Loading / content failed / vault locked / vault recovery | `App/RootView.swift` | — | — | blocked: needs a failing content pack or a locked/corrupt vault; no in-memory launch argument produces them |
| PREP-01 | Prepare top: rings over the first three actions | `Next/NextStepsView.swift`, `Next/ProgressRingsCard.swift` | `-demoTab prepare` | `rings.card`, `next.actions`, `next.step.*` | unverified |
| PREP-02 | Prepare method note and caveat (ⓘ open) | `NextStepsView` header | tap `next.info` | `next.about` | unverified |
| PREP-03 | Rings provisional caveat (ⓘ open) | `ProgressRingsCard` | tap `rings.info` | `rings.caveat` | unverified |
| PREP-04 | All actions shown | `NextStepsView.toDo` | tap `next.showAll` | `next.actions` | unverified |
| PREP-05 | Family panel | `Next/FamilySummaryCard.swift` | scroll to `family.panel` | `family.panel` | unverified |
| PREP-06 | Correction from the family panel: editor with that person expanded | `FamilySummaryCard` → `Next/FocusedHouseholdEditor.swift` | tap first `family.panel.person.*` | `focused.save`, `family.relationship.*` | unverified |
| PREP-07 | Whole-family editor from the panel | same | tap `family.panel.editAll` | `family.householdName` | unverified |
| PREP-08 | Family editor, new member (Name field + Relationship picker together) | `FocusedHouseholdEditor` | tap `next.family`, `family.addPerson` | `family.personName.*`, `family.relationship.*` | unverified |
| PREP-09 | First action's editor | `PreparationTaskEditor` targets | tap first `next.step.*` | — (target depends on the action) | unverified |
| PREP-10 | Questions card (three, then Show all) | `NextStepsView.questions` | scroll to `next.questions` | `next.questions` | unverified |
| PREP-11 | Recorded preparations (three, then Show all) | `NextStepsView.recorded` | scroll to `next.recordedSection` | — (absent when nothing is recorded) | unverified |
| PREP-12 | Scorecard | `Next/ScorecardCard.swift` | scroll to `score.card` | `score.card` | unverified |
| PREP-13 | Scorecard breakdown open (no rubric version shown) | same | tap `score.how` | — | unverified |
| PREP-14 | Supply inventory | `Next/SupplyInventoryView.swift` | tap `next.inventory` | `inventory.kind` | unverified |
| PREP-15 | Shopping list | `Next/ShoppingListView.swift` | tap `next.shopping` | `shop.kit` | unverified |
| PREP-16 | Where to go (shelters / cooling) | `Maps/WhereToGoView.swift` | tap `next.whereToGo` | — | unverified; network-dependent content (maps owner) |
| PREP-17 | Injected weather alert banner | `Next/AlertBannerCard.swift` | `-demoAlert tornado` | `alert.banner` | unverified |
| PREP-18 | Finish-the-card checklist | `NextStepsView.finishCard` | scroll to `next.finishCard` | — (absent once all three exist) | unverified |
| PREP-19 | Completed section with Undo / reopen | `NextStepsView.done` | needs a completed preparation | — | unverified; not driven by the inventory test (needs a completed preparation first) |
| CARD-01 | Family emergency card | `Next/OutageCardView.swift` | tap `next.outageCard` | `card.page` | unverified |
| CARD-02 | Add medical device (sheet) | `Next/MedicalSetupView.swift` | tap `next.outageCard`, `card.addDevice` | `medical.save` | unverified |
| CARD-03 | Card PDF preview (sheet) | `Plan/PlanViews.swift` `PDFPreviewSheet` | tap `next.outageCard`, `card.share` | `pdf.preview` | unverified |
| HOME-01 | Home, 2D plan | `Home/HomeTabView.swift`, `Spatial/FloorPlanView.swift` | `-demoHomeMode 2d`, tap `next.home` | `home.scene` | unverified |
| HOME-02 | Home, 3D dollhouse | `Spatial/DollhouseView.swift` | `-demoHomeMode 3d`, tap `next.home` | `home.scene` | unverified |
| HOME-03 | Home, room list | `Spatial/HomeRoomListView.swift` | `-demoHomeMode rooms`, tap `next.home` | — | unverified |
| HOME-04 | Room editor (sheet) | `Spatial/ManualHomeEditorView.swift` | rooms, tap first `home.editRoom.*` | `home.save` | unverified; house lead owns behavior |
| HOME-05 | Two-story home, upper floor | `FloorPlanView` | `-demoHome twostory -demoHomeFloor 1` | `home.scene` | unverified |
| HOME-06 | RoomPlan scanner, LiDAR preview, opening card, scan check | `Spatial/ScannerHomeView.swift`, `RoomCaptureContainer.swift`, `ScanCorrectionViews.swift` | physical scan | — | blocked: needs a person moving the phone through a real space (house lead) |
| HOME-07 | Photo review, site evidence | `Home/PhotoReviewView.swift`, `Home/SiteEvidenceView.swift` | Home links | — | unverified; photo consent path is AI-bearing (reviewer-only) |
| PLAN-01 | Plan tab | `Plan/PlanViews.swift` | `-demoTab plan` | `plan.familyCard` | unverified |
| PLAN-02 | Official help | `Help/HelpViews.swift` | tap `plan.help` | `help.outageCard` | unverified |
| PLAN-03 | Card pushed from help (was a third stacked sheet) | same → `OutageCardView` | tap `plan.help`, `help.outageCard` | `card.page` | unverified |
| PLAN-04 | Contacts editor: labelled Name / Relationship / Phone | `FocusedHouseholdEditor(.newContact)` | tap `plan.addContact` | `contacts.name.*`, `contacts.relationship.*`, `contacts.phone.*` | unverified |
| PLAN-05 | Home address editor (sheet) | `Maps/HomeAddressEditorView.swift` | tap `plan.address` | `address.save` | unverified |
| PLAN-06 | Neighborhood map (sheet) | `Maps/MapPlanningView.swift` | tap `plan.map` | — | unverified; maps owner; network tiles |
| PLAN-07 | Meeting place chooser (sheet) | same | tap `plan.meetup.outsideMeetingPoint` | — | unverified |
| PLAN-08 | Share choices (sheet) | `FamilyPlanShareView` | tap `plan.share` | `share.preview` | unverified |
| PLAN-09 | Share PDF preview (sheet on sheet) | `PDFPreviewSheet` | tap `plan.share`, `share.preview` | `pdf.preview` | unverified |
| PLAN-10 | Saved plan document | `PlanDocumentView` | `-demoPlan all`, tap `plan.viewSaved` | — | unverified |
| REH-01 | Rehearse list (practice card + six scenario cards) | `Rehearse/RehearseViews.swift` | `-demoTab rehearse` | `scenario.home-fire`, `practice.open` | unverified |
| REH-02 | Practice check start | `Rehearse/PracticeCheckView.swift` | tap `practice.open` | `practice.start` | unverified |
| REH-03 | Adaptive fire rehearsal, opening | `Rehearse/AdaptiveRehearsalView.swift` | `-demoScenario home-fire -demoAdaptive` | `adaptive.header` | unverified |
| REH-`<hazard>`-START | Rehearsal start, each of the six hazards | `RehearsalView` | `-demoScenario <hazard> -demoStep start` | `rehearsal.step` | unverified ×6 |
| REH-`<hazard>`-DECISION | Rehearsal at its first decision, each hazard | same | `-demoStep decision` | `decision.option.*` | unverified ×6 |
| REH-`<hazard>`-END | Rehearsal ended, each hazard | same | `-demoStep end` | `rehearsal.debrief` | unverified ×6 |
| REH-`<hazard>`-DEBRIEF | Debrief sheet, each hazard | `DebriefView` | end, tap `rehearsal.debrief` | `debrief.goPrepare` | unverified ×6 |
| REH-04 | Practice four-phase answers and retirement | `PracticeCheckView` | — | — | unverified; `DeviceAuditUITests.testPracticeCheckRecordsFourFirstAnswersBeforeFeedback` |
| SET-01 | Settings (sheet) | `Settings/SettingsView.swift` | tap `app.settings` | `settings.language`, `settings.done` | unverified |
| SET-02 | Settings, sample family chooser | `SampleFamilySection` | settings, scroll | `settings.sampleLoad` | unverified |
| SET-03 | Settings, delete everything | `SettingsView` | settings, scroll to `settings.delete` | — | unverified |

`<hazard>` is one of `home-fire`, `tornado`, `flash-flood`, `freeze-power-loss`, `heat-grid-strain`, `water-outage`.

## Beacon-bearing states (reviewer-only, not driven by the inventory test)

| ID | State | Driving test |
|---|---|---|
| AI-01 | Prepare tailored by Beacon (`next.ai`, `next.ai.applied`, replay label) | `BeaconUnpluggedUITests`, `DeviceAuditUITests.testGeminiPersonalizesThePrepareListWithinPriority` |
| AI-02 | On-device family briefing expanded (`next.briefing.expand`) | none yet; needs an iOS 26 device with Apple Intelligence |
| AI-03 | Beacon-directed rehearsal and debrief summary (`debrief.ai`) | `DeviceAuditUITests.testGeminiDirectsTheFictionalApartmentFireThroughValidatedCommits` |
| AI-04 | Beacon drill setup (`drill.ai.*`) | none in this branch |

## Sheet depth (deepest stacks after this branch)

- Plan → Share (sheet) → PDF preview (sheet) → system share sheet: kept, the share sheet is the system's.
- Prepare → finish meetup (sheet) → map destination (sheet) → place editor (sheet): maps lead scope; flagged.
- Plan → Help (push) → card (push, was a sheet) → add device or PDF preview (sheet): reduced by one layer.

## Variants still to record per entry

Ordinary and AccessibilityXXL text are driven by the two test methods; en/es/vi by `INVENTORY_LOCALE`. Light/dark,
smallest supported screen, keyboard shown/hidden and VoiceOver order are not driven automatically; record the
combinations actually captured against each ID.
