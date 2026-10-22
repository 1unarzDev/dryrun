# Native UI and experience lead — work record

Branch `lead/native-ui` from `cdb4098`. Requirements UI-01, UI-02 (reference §§11, 2A.2) and Beacon demo goal
milestone 6. No device reservation this wave: nothing here was launched on a phone or simulator, and no raw AI
output, AI-bearing capture or accessibility tree was opened. Evidence labels: **implemented**, **Mac-build**
(generic iOS, unsigned, `build-for-testing`), never device-verified.

## Visual rules

The same eight rules are in the header of `apps/ios/DryRun/App/Theme.swift`. Rule 6 symbols are the ones already used
on the strongest screens.

1. **Type.** Screen headline `.title2.bold`; card title `.headline`; row title `.body.semibold` (the first row of a
   ranked list may use `.title3.bold`); supporting text `.footnote` in secondary; caveats `.caption`/`.footnote`.
2. **Spacing.** Only `Theme.Space` (4/8/12/16/24/32). The screen gutter, card padding and the gap between cards are
   all `l` (16); inside a card `m` (12); label/value pairs `xs`/`s`. No one-off offsets for a single screenshot.
3. **Cards.** `SectionCard` for grouped content and `.cardSurface()` for tappable cards share one surface, corner
   (`Radius.card`) and hairline. Leading symbol tiles use `SymbolTile` (52 pt, `Radius.control`).
4. **Buttons.** One `.primary` per screen. `.secondary` goes beside it. In-card text actions use `.inline`
   (`ShowAllButton`, Undo/reopen, "See or correct everyone"). Every tap target is at least `Theme.minTap` (44 pt).
   Full-width buttons and choices use `Theme.comfortableTap` (52 pt; the secondary button grew from 48).
5. **Semantic color.** `accent` means identity and navigation. `critical` is only for an unmet essential requirement.
   `caution` means unknown or unconfirmed, and `success` means recorded or done, never safe. Ring colors
   (`ringPractice`, `ringOverall`) are identity colors, not status colors.
6. **Icons.** Use one leading symbol per card title or row, with no decorative repeats. Urgency and status icons go in a
   fixed trailing column, and icon-only controls carry an accessibility label. Family is `person.2.fill`, home is
   `house.fill`, the card is `person.text.rectangle.fill`, and a briefing is `text.quote`.
7. **Progressive disclosure.** Show at most `Theme.previewCount` (3) items before "Show all". Caveats and method notes
   sit behind `InfoButton` (ⓘ, 44 pt, with a label and a selected trait).
8. **Forms.** If two fields could be confused once filled (name and relationship, contact name and phone), each keeps a
   visible label (`LabeledTextField`, label leading, value trailing).

Other specialists should use these components and not restyle locally. A change to a shared component requires
checking the screens that use it (see the inventory).

## Feature-purpose records (§2A.2)

### 1. Prepare home: rings over the next three actions, caveats behind ⓘ (milestone 6)

- **Household and situation.** A non-technical family opening Prepare, often on a phone with large text.
- **Improves.** It answers "how far along are we and what do we do next" in one screen.
- **Inputs and unknowns.** It reads Core's provisional scorecard and Core's ranked actions. The rings show "–"
  until practice is assessed, and the provisional caveat is one tap away.
- **Why here.** `ProgressRingsCard` already existed (donor commit `7dac30b`) but nothing rendered it on this branch.
  It now sits directly above the action list. The scorecard further down keeps the cap reasons and breakdown.
- **Next action.** The first action is visible without scrolling at ordinary text (needs a device check). Each action
  is one tap away, as before.
- **Benefit and acceptance.** The method note and the "does not predict" footer move behind ⓘ next to the headline.
  Questions and recorded preparations preview three items with Show all, like the action list. Acceptance:
  PREP-01..04, 10, 11 captures at std and axxxl, with the first action above the fold at std, no ring/label
  truncation, and ⓘ reachable and announced.
- **Simpler option.** Dropping the rings and keeping only the scorecard was rejected because the owner's goal names
  rings. The rings carry no extra claim: same Core numbers, no green, caveat kept.

### 2. Family panel with consequential facts and direct correction (owner regression)

- **Household and situation.** Anyone checking that Dry Run knows who needs help.
- **Improves.** Before, the panel listed people and devices only when the on-device model was unavailable and had no
  action. Now `FamilySummaryCard` is always present (`person.2.fill`). It lists only people with assistance needs or
  essential equipment, plus unassigned essential devices: name · relationship, needs in sentence case, and what each
  fact means (step-free way out from Core's `requiresStepFreeRoute`, a power dependency, a cold-storage dependency).
- **Unknowns.** Nothing is inferred. If nothing consequential is recorded, the panel says so and invites the user to
  add it.
- **Why here.** It sits on Prepare beside the actions those facts drive. It replaced the roster inside the on-device
  briefing card, which now holds only the written briefing and uses its own symbol.
- **Next action.** Tap a row to open the family editor with that person already expanded (new
  `FocusedHouseholdEditor(focus:expanding:)`), or open the device's medical editor. That is one push. Before, it was
  the "Your family" tile, then finding the person, then expanding them: three steps.
- **Acceptance.** PREP-05..07 captures. Check alignment with the card text edge, the chevron in a fixed trailing
  column, multiline names at axxxl, and that Save returns to Prepare with the panel updated (state evidence, not
  only a screenshot).
- **Simpler option.** Keeping only the quick tile was rejected: the owner asked for consequential facts and a direct
  route.

### 3. Name vs relationship and capitalized disability labels (owner regression)

- **Family editor.** The relationship picker (and the custom role field) now sits directly under the labelled Name
  field for every member. Before, it was hidden inside the collapsed details. Name is typed and role is chosen,
  and both stay visible.
- **Contacts.** Name, Relationship and Phone use `LabeledTextField`, so their labels survive typing. Before, they
  were placeholder-only.
- **Setup.** The member field is labelled "Name (optional)", with the nickname hint as its prompt.
- **Disability labels.** `DisplayNames.need` gives sentence case for standalone labels in setup and editor toggles
  and the communication-support field. Lowercase text stays where it sits inside a sentence or a "·" summary. The
  vehicle row said "uses a wheelchair" for a vehicle property; it now uses the existing "Step-free / wheelchair
  access confirmed".
- **Acceptance.** PREP-08 and PLAN-04 captures. Check that the label is visible with a filled value at std and axxxl,
  and that capitalized toggles appear in en/es/vi.

### 4. Sheet depth

The Help card was presented as a sheet even though Help is pushed from Plan, and the card's editor and PDF preview
are themselves sheets. It is now pushed (PLAN-03), and the critical red is replaced by the accent card symbol. Other
deep stacks are listed in the inventory. The meetup map chain belongs to the maps lead.

### 5. Shared card surface and symbol tile in Rehearse

The practice and scenario cards used literal 52/14 values and no hairline. They now use `SymbolTile` and
`.cardSurface()`, the same surface as `SectionCard`. This is presentation only.

## Coordination notes

- **Prepare lead** (`Next/**`): my edits in `NextStepsView.swift` are confined to commit `318316e` (ProgressRingsCard
  placement, header ⓘ, the three-item previews, FamilySummaryCard placement, removal of the roster from the
  briefing) and a single identifier in `8626897`. `FocusedHouseholdEditor` gained an `expanding:` initializer. All
  existing call sites compile unchanged.
- **Rubric version.** No family-facing rubric version is rendered on this branch (`ScorecardCard` shows only
  localized criteria). The rubric remains in Core. Nothing to remove; PREP-13 is the capture that confirms it.
- **Reconnect feature.** I found no standalone Reconnect screen in my scope. However,
  `FocusedHouseholdEditor.preparationFields` still labels a `reconnect` preparation id generically. Whether Core
  still emits such a task is for the Prepare lead to confirm.
- **Translations.** Eight new keys in `common.json` (EN plus ES/VI drafts). `translation-baseline.json` gained
  entries for those keys only. 584 pre-existing `common` keys in es/vi have no baseline entry at base `cdb4098`, so
  the public-api translation-drift test is expected to fail before and after this branch. I did not record them,
  because that would hide real drift. Owner decision needed.

## Commands run (Mac only)

- `xcodegen generate` and `xcodebuild build-for-testing -project DryRun.xcodeproj -scheme DryRun -destination
  'generic/platform=iOS' -derivedDataPath /tmp/dryrun-native-ui-dd CODE_SIGNING_ALLOWED=NO`: **TEST BUILD
  SUCCEEDED** at base `cdb4098` and again after the final commit. That is the app, DryRunTests and DryRunUITests,
  including `UIInventoryUITests`.
- No device or simulator run. None of the new or changed UI tests has executed yet.

## Wave 2 (branch `lead2/native-ui` from `bd6974a`)

Inputs: the wave-1 audit (gate NOT ACCEPTED), `released/report-ui-inventory-physical-en-es-vi-std-ax-20261022` and
`released/report-phone-reviewer-wave1-tests-lead-checks-20261022`. No device reservation: nothing in this wave was
launched on a phone or simulator, and no raw AI output, AI-bearing capture or accessibility tree was opened.
Evidence labels: **implemented**, **Mac-build**, **Mac-test** (Core/public-api on this Mac). Nothing here is
device-verified.

### 1. Honest Beacon copy (CODEX-01), commit `574e523`

- **Problem.** Consent and detail text named Google Gemini as the provider and promised "no names, phone numbers or
  address". Codex is primary, and every example-household bridge sends `AuthorizedAIContext`: people, needs,
  medicines and equipment, contacts with phone numbers, home geometry, private location, saved places, supplies,
  tasks, practice sessions and scores.
- **Now (en/es/vi).** `adaptive.cloud.detail`, `prep.ai.detail` and `map.geminiPlansDetail` list the full record and
  the chain: OpenAI Codex first, then Google Gemini or Groq if Codex is unavailable, and this phone when offline.
  `map.geminiPlans`, `map.plannedByGemini`, `map.geminiRejected` and `map.geminiUnavailable` now say "Beacon". The
  keys are unchanged, so the Swift call sites and the `map.geminiPlans` accessibility identifier stay valid.
- **Photos.** `photo.consent` still names Gemini (`HomeReviewBridge` sends `providerConsent ["gemini"]`, and Codex
  has images=false). `photo.consentDetail` now says the photo goes only to Gemini, not to Codex or Groq, and it
  lists the context sent with it. The old wording also claimed "no names…" there, which was false.
- **Settings > About.** It now renders `native.aboutBeacon`, which before this wave had no call site and still
  claimed Anthropic/OpenAI/Groq and "never sent". The new text says: example households only; Codex first, then
  Gemini or Groq; photos go only to Gemini; the full record is sent; offline the app still plans, rehearses and
  scores; the user's own household is not sent. The last claim was checked against the source: every cloud bridge
  guards `household.isFictional`, and intake/briefing/explanations use on-device FoundationModels.
- **New keys for the codex lead.** These have no call sites yet:
  - `beacon.servedBy.codex|gemini|groq|local`, rendered by the new `BeaconServedByLabel(servedBy:)` in `Theme.swift`.
    It is DEBUG-only, takes allowlisted values only, and carries the identifier `beacon.servedBy`.
  - `adaptive.director.codex`, so that `adaptive.director.\(DirectorSource.rawValue)` resolves once `.codex` exists.
  - `adaptive.director.fallbackNote`, for the director deadline note.
- **Remaining copy debt (not mine to change).** `AppModel.refreshCloudResourcePlans` and the
  `resourcePlansFromGemini` names, and the comment "Asks Gemini once…", are orchestrator-owned identifiers. They are
  not user-visible.

### 2. AX truncation, commit `8766529`

- **PREP-08.** The new `View.readablePickerStyle()` in `Theme.swift` keeps `.menu` at ordinary sizes. At
  accessibility sizes it switches to `.navigationLink`: the row shows label and value wrapped, and the choices push a
  full-width list. It is applied to the family editor's relationship, age, start room and helper pickers (whole-family
  and single-person forms) and to the contact-role picker. Every `FocusedHouseholdEditor` presentation is pushed or
  wrapped in a `NavigationStack`. I checked all call sites.
- **PLAN-06 (es AX).** The map sheet's `map.privacy` qualifier, the planning summary and the route note now use
  vertical `fixedSize`, with the qualifier leading-aligned at full width. Before, the map below compressed them to
  one truncated line.
- **Not fixed.** The segmented Map/List control does not scale with Dynamic Type. That is native UIKit behaviour,
  and the maps lead owns the layout.

### 3. PREP-17 alert banner, commit `b7e3fed`

The `NextStepsView` call site (`if let alert = model.weatherAlert { AlertBannerCard(alert:) }` under the header) and
the 5-minute `refreshWeatherAlert()` loop are ported from `2a9d974`. `AppModel.refreshWeatherAlert` already returns
nil for in-memory runs unless `-demoAlert` is given. Before this change `-demoAlert` never surfaced: nothing called
`refreshWeatherAlert` at launch. The inventory entry PREP-17 is kept and needs a phone rerun.

### 4. Same-family reload hang, commit `b8ca532` (separate, orchestrator-owned AppModel edit)

- **Root cause (source).** Reloading the active example saves the same fixture revision, so `currentKey` is
  unchanged. Meanwhile `invalidateDerived()` clears `nextStepResults` and invalidates `nextGate`, and any in-flight
  run's result is discarded. `NextStepsView`'s `.task(id: currentKey)` therefore never re-runs, and "Running all six
  practice scenarios" stays on screen.
- **Fix.**
  - `nextStepsRefreshID` combines the key with a generation that `invalidateDerived` bumps. The view keys its task
    on it.
  - A second call for the same ID returns early, so the first run applies.
  - The six runs race a 45 s deadline as unstructured work. That lets the wait actually end; a task group would
    wait for every child.
  - On error or timeout, `nextStepsStalled` is set and Prepare shows `ui.next.timeout` with Try again (`next.retry`,
    which calls `retryNextSteps()`).
- **Tests.** `DryRunTests/PrepareReloadTests.swift` adds two tests: a same-example reload re-keys and recomputes, and
  concurrent refreshes finish. Both compile only. They have not run.

### 5. Drifted tests, commit `6a43e66`

- **MapRequestTests.** The fake search now tags hospital-query results with `MKPointOfInterestCategory.hospital`,
  because discovery drops untagged ones. A new test covers the vet-clinic drop. This fixes the 1/68 unit failure;
  it is not yet re-run on the phone.
- **SixHazardUITests and the DemoJourney address journey.** `rehearsal.next` now decides between advancing and
  answering. It is enabled exactly when no decision is pending (`RehearseViews.controls`). After an answer, the test
  waits for that `decision.option.*` to disappear. The address journey taps `rehearsal.setup.start`, because normal
  entry opens setup first.
- **DemoJourney describe.** The county is chosen in Help (`plan.help` then `county.picker`). The create form now has
  it below the contact section.
- **UIInventory.** ONB-03 asserts `intake.text` and `setup.finishLater`. HOME-04 taps `home.edit` before
  `home.editRoom.*`.
- **Not changed.**
  - `DeviceAuditUITests.testPracticeCheckRecordsFourFirstAnswersBeforeFeedback` may be a real regression. It is in
    the scenario lead's scope.
  - `testAdaptiveApartmentFireCommitsActionsFromReceipts` fails because of the director stall. That is the codex
    lead's issue.

### 6. Translation-drift baseline: owner decision (not bulk-recorded)

I added baseline entries only for the keys I re-translated this wave (17 per locale) and for the twelve
Gemini→Beacon keys. I checked the es/vi text of those twelve against the current English: `adaptive.director.gemini`,
`adaptive.cloud.toggle`, `adaptive.fallback.rejected`, `adaptive.fallback.unavailable`, `prep.ai.title`,
`prep.ai.run`, `prep.ai.working`, `prep.ai.applied`, `prep.ai.unavailable`, `prep.ai.whyLabel`, `prep.ai.ideas` and
`prep.ai.question`.

The drift test fails before and after this branch: 377 stale entries per locale at `bd6974a`, 358 now. All 358 are
"no baseline". None is "English changed". The same keys are stale in es and vi. The owner can choose one of these:

- (a) Have a reviewer confirm each translation against current English, then record it with
  `node scripts/record-translation-baseline.mjs es vi`.
- (b) Accept the drafts as the baseline in one recorded commit, with a ledger note.

Exact keys (es and vi identical):

- `common/map.*` (11): `map.hardware`, `map.hardwarePlanningNote`, `map.forTasks`, `map.forTasksFooter`, `map.forTasksEmpty`, `map.forTasksNone`, `map.forTask`, `map.forTaskTask`, `map.forTaskMarker`, `map.notVerified`, `map.plannedOnPhone`
- `common/common.*` (1): `common.tab.scan`
- `common/alert.*` (34): `alert.title`, `alert.sample`, `alert.until`, `alert.doNow`, `alert.rehearse`, `alert.official`, `alert.noRehearsal`, `alert.demoToggle`, `alert.demoNone`, `alert.demoFooter`, `alert.kind.tornado`, `alert.kind.flash-flood`, `alert.kind.heat`, `alert.kind.winter`, `alert.step.tornado-go-room`, `alert.step.tornado-go-lowest`, `alert.step.tornado-move-helper`, `alert.step.tornado-move-nohelper`, `alert.step.tornado-bring-backup`, `alert.step.tornado-shoes-light`, `alert.step.flood-no-driving`, `alert.step.flood-charge`, `alert.step.flood-move-helper`, `alert.step.flood-move-nohelper`, `alert.step.flood-higher`, `alert.step.heat-check-person`, `alert.step.heat-cold-storage`, `alert.step.heat-charge`, `alert.step.heat-cool-room`, `alert.step.freeze-charge`, `alert.step.freeze-fill-water-well`, `alert.step.freeze-fill-water`, `alert.step.freeze-warm-person`, `alert.step.freeze-safe-heat`
- `common/shop.*` (52): `shop.title`, `shop.open`, `shop.intro`, `shop.kit.budget`, `shop.kit.complete`, `shop.budget`, `shop.total`, `shop.tier.medical`, `shop.tier.lifeSafety`, `shop.tier.basics`, `shop.bought`, `shop.markBought`, `shop.empty`, `shop.skipped`, `shop.prices`, `shop.qty.gallon`, `shop.qty.personDay`, `shop.qty.each`, `shop.qty.pack`, `shop.qty.wattHour`, `shop.qty.petWeek`, `shop.qty.infantWeek`, `shop.qty.person`, `shop.item.water-gallon`, `shop.item.food-person-day`, `shop.item.flashlight`, `shop.item.batteries-aa`, `shop.item.first-aid-kit`, `shop.item.weather-radio`, `shop.item.power-bank`, `shop.item.battery-station-wh`, `shop.item.medication-cooler`, `shop.item.pet-food-week`, `shop.item.pet-carrier`, `shop.item.infant-supplies-week`, `shop.item.fire-extinguisher`, `shop.item.emergency-blankets`, `shop.reason.medical-power`, `shop.reason.medical-power-estimated`, `shop.reason.medication-cold`, `shop.reason.extinguisher`, `shop.reason.flashlight`, `shop.reason.batteries`, `shop.reason.radio`, `shop.reason.blankets`, `shop.reason.water`, `shop.reason.food`, `shop.reason.first-aid`, `shop.reason.power-bank`, `shop.reason.pet-food`, `shop.reason.pet-carrier`, `shop.reason.infant`
- `common/places.*` (31): `places.title`, `places.intro`, `places.from`, `places.noOrigin`, `places.kind.openShelter`, `places.kind.coolingCenter`, `places.kind.warmingCenter`, `places.noShelters`, `places.sheltersUnavailable`, `places.source`, `places.stated.wheelchairAccessible.true`, `places.stated.wheelchairAccessible.false`, `places.stated.adaCompliant.true`, `places.stated.adaCompliant.false`, `places.noAccessInfo`, `places.pets`, `places.callPower`, `places.call`, `places.route`, `places.drive`, `places.walk`, `places.routeSummary`, `places.routeNote`, `places.routeFailed`, `places.forHousehold`, `places.note.power-person`, `places.note.power`, `places.note.cold`, `places.note.step-free`, `places.note.pets`, `places.open`
- `common/rings.*` (7): `rings.preparation`, `rings.practice`, `rings.overall`, `rings.done`, `rings.start`, `rings.provisional`, `rings.info`
- `common/debrief.*` (5): `debrief.ai.title`, `debrief.ai.working`, `debrief.ai.first`, `debrief.ai.note`, `debrief.ai.unavailable`
- `common/drill.*` (5): `drill.ai.title`, `drill.ai.run`, `drill.ai.working`, `drill.ai.note`, `drill.ai.unavailable`
- `common/resource.*` (26): `resource.purpose.water`, `resource.purpose.food`, `resource.purpose.light`, `resource.purpose.alarms`, `resource.purpose.firstAid`, `resource.purpose.medication`, `resource.purpose.equipment`, `resource.purpose.heatCold`, `resource.purpose.officialPlanning`, `resource.unknown.stock`, `resource.unknown.outageOperation`, `resource.unknown.eligibility`, `resource.unknown.hours`, `resource.unknown.compatibility`, `resource.unknown.activation`, `resource.unknown.access`, `resource.evidence.callAhead`, `resource.evidence.manufacturer`, `resource.evidence.official`, `resource.boundary.policeStation`, `resource.boundary.fireStation`, `resource.boundary.trustedMeetup`, `resource.boundary.hospital`, `resource.boundary.warmingCooling`, `resource.boundary.shelter`, `resource.boundary.equipmentSupplier`
- `common/site.*` (81): `site.title`, `site.homeFooter`, `site.intro`, `site.needsCounty`, `site.otherAddress`, `site.status`, `site.recorded`, `site.notRecorded`, `site.kind.elevation`, `site.kind.flood`, `site.kind.wildfire`, `site.kind.hurricane`, `site.flood.unknown`, `site.flood.aboveDesignLevel`, `site.flood.belowDesignLevel`, `site.flood.overlappingUncertainty`, `site.wildfire.rating`, `site.wildfire.veryLow`, `site.wildfire.low`, `site.wildfire.moderate`, `site.wildfire.high`, `site.wildfire.veryHigh`, `site.hurricane.recorded`, `site.sources`, `site.sourceDates`, `site.sourceCounts`, `site.sourceDoesNotCount`, `site.add`, `site.limits`, `site.limit.terrain`, `site.limit.wildfire`, `site.limit.hurricane`, `site.limit.scope`, `site.remove`, `site.removeConfirm`, `site.value`, `site.uncertainty`, `site.units`, `site.feet`, `site.meters`, `site.datum`, `site.datumHint`, `site.surface`, `site.terrain`, `site.finishedFloor`, `site.zone`, `site.route`, `site.source`, `site.publisher`, `site.url`, `site.retrieved`, `site.validUntil`, `site.copied`, `site.review`, `site.reviewTitle`, `site.reviewBody`, `site.save`, `site.saveFailed`, `site.problem.source`, `site.problem.copied`, `site.problem.number`, `site.problem.datum`, `site.problem.zone`, `site.lookup.section`, `site.lookup.flood`, `site.lookup.elevation`, `site.lookup.needsAddress`, `site.lookup.consentTitle`, `site.lookup.consentFlood`, `site.lookup.consentElevation`, `site.lookup.send`, `site.lookup.working`, `site.lookup.zone`, `site.lookup.sfha`, `site.lookup.bfeFilled`, `site.lookup.noBFE`, `site.lookup.notMapped`, `site.lookup.ambiguous`, `site.lookup.elevationFilled`, `site.lookup.noElevation`, `site.lookup.failed`
- `common/photo.*` (33): `photo.title`, `photo.intro`, `photo.choose`, `photo.pick`, `photo.preview`, `photo.synthetic`, `photo.minimized`, `photo.room`, `photo.roomUnknown`, `photo.discard`, `photo.consent`, `photo.send`, `photo.noService`, `photo.failed`, `photo.results`, `photo.none`, `photo.category.possibleObstruction`, `photo.category.tripHazard`, `photo.category.supplyAccess`, `photo.seen`, `photo.couldBe`, `photo.decision.confirmed`, `photo.decision.dismissed`, `photo.decision.uncertain`, `photo.decided.confirmed`, `photo.decided.dismissed`, `photo.decided.uncertain`, `photo.notSafe`, `photo.linked`, `photo.linkedExits`, `photo.linkedSupplies`, `photo.noPoints`, `photo.needsHome`
- `native/ui.*` (4): `ui.scene.accountedOutside`, `ui.scene.exitedNeedsAccounting`, `ui.scene.reachedShelter`, `ui.brief.cloudNote`
- `native/native.*` (10): `native.sampleFamily`, `native.sampleFamilyDetail`, `native.sampleFamilyPick`, `native.sampleHomePick`, `native.sampleFamilyLoad`, `native.sampleFamilyBlocked`, `native.sampleKeepHome`, `native.sampleReplaceHome`, `native.sampleReplaceHomeConfirm`, `native.restoreHousehold`
- `spatial/spatial.*` (58): `spatial.review-captured-home`, `spatial.scanner.title`, `spatial.scanner.intro`, `spatial.scanner.device`, `spatial.scanner.lidar`, `spatial.scanner.roomplan`, `spatial.scanner.camera`, `spatial.scanner.yes`, `spatial.scanner.no`, `spatial.scanner.camera-on`, `spatial.scanner.camera-off`, `spatial.scanner.camera-ask`, `spatial.scanner.live`, `spatial.scanner.live-detail`, `spatial.scanner.live-start`, `spatial.scanner.live-stop`, `spatial.scanner.center`, `spatial.scanner.points`, `spatial.scanner.confident`, `spatial.scanner.near`, `spatial.scanner.far`, `spatial.scanner.scan`, `spatial.scanner.scan-detail`, `spatial.scanner.result`, `spatial.scanner.no-scan`, `spatial.scanner.area`, `spatial.scanner.walls`, `spatial.scanner.to-confirm`, `spatial.scanner.open-home`, `spatial.scanner.rehearse`, `spatial.scanner.sim`, `spatial.scanner.interrupted`, `spatial.card.what`, `spatial.card.door`, `spatial.card.window`, `spatial.card.doorway`, `spatial.card.none`, `spatial.card.leadsTo`, `spatial.card.outside`, `spatial.card.notSure`, `spatial.card.notUsable`, `spatial.card.notUsableNote`, `spatial.card.restore`, `spatial.card.more`, `spatial.card.progress`, `spatial.card.skip`, `spatial.card.confirm`, `spatial.card.checked`, `spatial.card.checkedDetail`, `spatial.card.checkTitle`, `spatial.card.done`, `spatial.card.scanSection`, `spatial.card.check`, `spatial.card.removed`, `spatial.card.revert`, `spatial.card.revertConfirm`, `spatial.card.undoSave`, `spatial.card.redoSave`

### Commands run (Mac only)

- `xcodegen generate` and `xcodebuild build-for-testing -project DryRun.xcodeproj -scheme DryRun -destination
  'generic/platform=iOS' -derivedDataPath /tmp/nui2/dd CODE_SIGNING_ALLOWED=NO`: **TEST BUILD SUCCEEDED** after all
  five commits. That covers the app, DryRunTests including `PrepareReloadTests`, and DryRunUITests.
- `swift test` in `packages/DryRunCore`: 649 Swift Testing tests in 119 suites passed. XCTest: 27 executed, 3
  skipped, 0 failures. Core is unchanged; this run checks the locale edits against Core content tests.
- `pnpm test -- test/locales.test.ts` in `services/public-api`: 66 passed, 2 failed. The 2 failures are the existing
  es/vi drift tests (358 no-baseline entries each). Placeholder and number preservation, draft marking and the
  key-subset checks pass.
- No phone or simulator run. None of the changed native or UI tests has executed.
