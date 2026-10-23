# Native UI specialist work record

Owner: native_ui. Requirements UI-01, UI-02, PREP-01, HOME-02, REVIEW-01. Base 26332de; shared working checkout, no independent commit. Scope: Theme.swift, NextStepsView.swift styling, FocusedHouseholdEditor.swift and HouseholdSetupView.swift presentation. Integration owner retains async mutation callbacks. Device exclusively reserved by output_review; user requires plugged-in iPhone 16 Pro. No device commands, raw outputs, captures, persisted AI, logs or accessibility trees inspected by this specialist.

## Purpose and changes

A family identifying its next preparation needs a stable title edge and honest urgency. Source showed urgent warning inserted before title and teal effort badge next to red urgent treatment. Move warning to fixed-width trailing state column; apply urgency color to effort badge; retain explicit critical accessibility label and hazard icons. No action or scoring semantics changed.

A person correcting family information must distinguish name from relationship. Persist the Name label alongside editable names in focused family form and added create-form members; keep Relationship picker separate. Remove relationship-as-name-placeholder. Family briefing uses existing person.2.fill symbol. Remove standalone reconnect preparation form from family editor, preserving stored preparation record, contacts, meetup flows and review state. Family editor now moves directly from member corrections to review together, with one less unrelated section.

Journey: Prepare > family shortcut > edit name/details > Save (unchanged, one push). Prepare > task (unchanged, one push). Create > additional member name (same form, no new navigation). Simpler option: retain focused existing forms, change presentation only rather than add a wizard/panel.

## Shared design rules

- Use existing Theme.Space, Radius, semantic colors and minimum 44-point tap targets. Keep headings and task body on a stable leading edge; warnings occupy a trailing status region.
- Pair urgency with symbol/accessible text; effort badges follow the task semantic tint. Do not rely on color alone.
- Use person.2.fill for the family grouping, house for home, card symbol for the emergency card; omit decorative duplicate symbols where they impede reading.
- Preserve intrinsic multiline height; use adaptive stacks for constrained width/accessibility text. Never resize app wording for a screenshot.
- Form field purpose remains visible while editing. Name and family role are different facts. Save failure keeps draft; saving/cancel/persistence contracts remain integration-owned.
- Shared SectionCard/buttons unchanged pending actual-device evidence; no broad redesign from source-only guesses.

## Acceptance / verification

Implemented-source only; no native appearance claim. Root owns signed build and physical integration runs. Requested output_review matched ordinary/accessibility iPhone captures of urgent/ordinary rows, expanded family briefing, family name/role editing and create additional-member field; exact recorded fixtures hh-oak/hh-lake/hh-pine, locale and build must accompany review. Require no title overlap, multiline effort visibility, family icon, stable labels, reachable Save and VoiceOver label order. Save/relaunch must use state evidence, not screenshots.

Native regression scope includes shared row consumers, English/Spanish/Vietnamese, light/dark, ordinary/accessibility text, keyboard-visible/hidden. Disability capitalization, rubric-version exposure, obsolete reconnect task entry points outside this form remain broader audit checks; do not infer complete removal from this one edit. No new tests added for reversible presentation-only changes. Build through protected capture and reviewer-cleared diagnostic needed. No protected output viewed.

## Completed donor native restoration checkpoint

Donors exact-cleared by report-local-branch-production-source-clearance: a9efc8f PhotoReviewView/SiteEvidenceView; 5f95135 ScannerHomeView/LiDARDepthPreview/ScanCorrectionViews. Added Home links preserve the current three primary tabs. Existing current Home editor, scan pending draft, Save/revision/scope and AX changes retained. Scanner modifier adapted to current async Bool save contract; no ManualHomeEditor replacement. Correction controls are available for root to integrate in editor. Photo results use snapshot/scope/operation guards and generic failure presentation; site lookup guards and editor context invalidation added. Photo actions adapt at accessibility sizes. Settings example selection/restore uses explicitly separate-store AppModel APIs agreed by root/scenario specialist; never keeps private geometry in a synthetic family. Root owns store/client implementation and required locale resources. Demo adaptive launch/homeFloor parsing and Root adaptive initial path restored; no fourth Scan tab imported. DisplayNames preserves first-letter capitalization for localized need labels.

Pending gates: required AppModel/client/Core APIs, exact authored locale resource clearance/integration, protected signed build, reviewer-only physical execution. Scanner real sensor/RoomPlan, photo consent/send/confirmation/context switch, site lookup/source/date/save, separate example-store restore require current iPhone evidence. No native success claimed from imported source. Root specifically requested source edits freeze after this checkpoint. No device accessed.

## Native feature entry integration checkpoint

Assigned NextStepsView/RehearseViews restored reachable feature value without replacing the current authored scene renderer or compact AX row fixes. Prepare now has one explicit restored PreparationAICard invocation with accepted within-tier ordering and explanations; the earlier direct GatewayPreparationService invocation was removed. Optional on-device briefing is only available when the restored provider feature is unavailable. Existing task-first order retained; inventory, shopping, local destination, and deterministic score controls are reachable in Prepare. Score refresh binds to scoreKey. Rehearse exposes PracticeCheckView and recognizes adaptive routes, including a direct authored-intro link. Existing primary tabs unchanged. ScorecardCard no longer renders technical rubric version; provenance remains in Core/runtime.

Files: Next/NextStepsView.swift, Rehearse/RehearseViews.swift, Next/ScorecardCard.swift. Verified only scoped git diff --check (passed), required label keys found in current authored locale scope. No compile/native execution by specialist; root/scenario compile owner must run protected generic iOS build. Physical device unavailable per new work order; no phone testing inferred. Current phone acceptance remains pending for entry reachability, four-phase practice transitions, personalized rows, context switching and score/inventory persistence. GatewayPreparationService source retained unreferenced pending integration cleanup. Source frozen after this checkpoint.

## Source-only advice-depth / decision-position refinement

Reviewed released report-family-experience-journey-persistence-1 and report-integrated-native-ui-matched-1; no originals opened. Changes: PreparationAICard optional unscored ideas now use one disclosure (existing title; full generated content retained), leaving accepted count and question visible. Scope switch collapses the disclosure. AdaptiveRehearsalView scrolls to the start of a pending decision instead of its bottom, including initial observation; long accessibility-size option groups should begin with the prompt rather than their last option. Current scene/context remain fully scrollable. No scoring, practice evidence, command, routing or request semantics changed. Files: Next/PreparationAICard.swift, Rehearse/AdaptiveRehearsalView.swift. PracticeCheckView unchanged.

Acceptance pending: protected generic-iOS compile; later reviewer-owned iPhone16Pro ordinary/AccessibilityXXL run with tall choices, resumed pending decision, reduced motion and all six hazards. Confirm prompt begins below navigation chrome, first option reachable, no focus jump during answer, full ideas open/readable, keyboard/VoiceOver disclosure state, family switch collapses ideas. No native verification possible while phone unplugged. Optional ideas now take one explicit expansion; this is intentional progressive disclosure rather than text removal. Preparation intro/953pt task placement remains outside this edit scope and requires full-screen matched review after integration.

## Choice formats: rehearsal and practice (hour/options)

Owner: "some questions will have tens of choices which make it difficult for the user to choose."

### Where options are rendered (inventory)

| Screen | Source of options | Before | After |
| --- | --- | --- | --- |
| Adaptive exercise, "Your choices" (`rehearsal.cmd.list`) | `HazardChoices.options` (host-validated `feasibleCommands`) | One full-width button per command. Commands multiply person x exit/room x purpose: fire with 4 people and 3 exits = 12 escapes + accompany + account-outside, roughly 15-20 rows | `ChoicePicker`: at most 5 flat rows; otherwise 1. What (action-kind chips with counts), 2. Who (avatar chips), 3. Choose one (destination-led rows, at most 4 + "More (n)") |
| Adaptive exercise, "Other actions" | water policy, power (device x backup + none), contacts, door x person (fire), helper pairs | Flat list, often 10+ (doors x people alone can exceed 10) | Same `ChoicePicker` |
| Adaptive exercise, recognition notes | `recognizeGap` choices | Flat list | Same `ChoicePicker` |
| Adaptive/practice "Move someone" | household people, home rooms | Two menu pickers (hidden lists, room list can be 10+) then a button | `PersonRoomPicker`: avatar chips, room chips (5 + "More rooms"), one confirm button (`adaptive.moveGo` / `practice.moveGo`) |
| Practice check action list (`practice.actions`) | `ExerciseActions.candidates` previewed by the host | Flat list, same multiplication as above | `ChoicePicker` |
| Decision card (authored choice points, adaptive + practice + classic rehearsal) | `ScenarioLibrary` choice points | Flat text buttons (typically 3-4) | `ChoicePicker` flat mode with letter icons (a, b, c...) so options can be read aloud; "More" only past 5 |
| Setup questions (`rehearsal.setup.*`) | authored setup questions | Radio rows with selected state | Unchanged (already few options, clear selection) |
| Starting assumptions (room per person) | home rooms | Menu pickers | Unchanged (collapsed in a disclosure, not a decision moment) |

Largest visible decision before: every option at once (15-20 rows on a 4-person fire). After: at most 6 kind chips +
the people row + 5 rows; the rest one tap away.

### Rules the picker follows

- Never decides or styles a "right" option; order is the host's ranking (primary objective first, household order).
- Data comes only from Core (`HazardChoice` purpose/person/room) and authored content; no AI text.
- Final rows keep their accessibility identifiers (`rehearsal.cmd.<kind>.<target>.<value>`, `decision.option.<id>`)
  and commit with one tap as before; the full sentence stays the accessibility label even when the row leads with the
  destination. Chips carry `choice.group.<kind>`, `choice.person.<kind>.<personID>`, `choice.movePerson.*`,
  `choice.moveRoom.*`, `choice.more`.
- Selected state = fill + outline + checkmark (never color alone); chips are at least `Theme.comfortableTap` tall.
- Headings ("What", "Who", group names) are English with an optional `choice.*` locale key, so no translated locale
  becomes incomplete.

### Tests

`HazardChoiceUITests` gained `narrow(to:)`: when a target is not visible it taps each kind chip and then each person
chip. Caveat: "not offered again" assertions (`XCTAssertFalse(prefixed(...).exists)`) only see the selected
group now, so they are weaker; they were not re-run here (no simulator launches in this task).

### Not done (next)

- Floor-plan mini map with tappable rooms as the "where" level (the room chips are the fallback).
- Setup room pickers as chips.
