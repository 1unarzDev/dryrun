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
