# UI audit — October 17 revision

## First-run pass — October 18 (Claude, simulator iPhone 17e, in-memory store)

Goal for this pass (owner's answers): the first 60 seconds for a judge, and a real family reaching a useful card in
under two minutes. Two independent walk-throughs of the running app (fresh onboarding → "See how it works" → freeze
rehearsal → debrief → Prepare/Plan; and "Set up my household" → card) found the problems below; each was fixed and
re-checked on the simulator.

| Screen | Found | Change |
|---|---|---|
| Plan card summary, card | Fully populated demo family read "Parent A: Not provided or not selected for this export" ×3 and "Still missing: Critical information, Last reviewed" | Core: with every clinical selection off, the critical section is one neutral line ("Critical information is turned off for sharing…") that never counts as missing; per-person lines appear only when that content is selected and read "Nothing recorded". Summary lists people with recorded needs first (Grandpa was hidden by `prefix(3)`), counts critical as missing only when nobody has anything, and no longer lists the review date as missing. "See how it works" turns all card content on for the example family; creating a real household or deleting everything resets to the opt-in default |
| Onboarding | Both paths below ~95 words; three example-household cards competed with the two buttons | Shorter bullets; both buttons above the fold; a one-line note under each button; other examples behind a collapsed disclosure |
| Rehearsal start | Empty box "Tap Next step to begin." and "Step 1 of 18" before anything happened | Intro card: scenario blurb, "You are practicing as Oak household (fictional): 4 people · Oxygen concentrator · …", example pill, how it works; label reads "18 steps" until the first step |
| Decision | Choosing made the card vanish with no feedback until the debrief, ten taps later | "You chose" card with the option and its feedback sentence appears immediately after choosing and stays while the exercise is at that moment |
| Debrief | Ended on "Still unconfirmed" with no way forward; Done returned to step 19 | Ends with "Set up my household" (example family; pushed inside the same sheet, saving replaces the example household and lands on Prepare) and "See what to prepare next" (switches to Prepare and pops Rehearse) |
| Create household | Only exit was a list row "Finish later" hidden under the keyboard; a stray "Not sure / not provided" row; no contact asked, so the card had no phone number | Sticky "Save and continue" button (hidden while typing, keyboard toolbar Done), name hint, one "Someone to call in an emergency" name + phone, shorter address footer. Blank rows are dropped on save; a failed save keeps the draft |
| Prepare (new household) | Landed on whatever tab was open before; "Do next (25)" starting with a tornado shelter; tiles below the fold; list visibly reordered a second after landing | "Finish your emergency card" checklist (contact · near meetup · backup meetup, each opening its editor) above the tiles, tiles above Do next; shown until all three exist. Waits for the six runs before listing. New household gets a fresh Prepare stack at the top; returning to onboarding resets to Prepare |
| Settings | Delete dialog showed no Cancel | Explicit Cancel |
| Copy | "Practice changes nothing until you mark a step done", "record the answer in its focused form", "These records satisfy their preparation checks…", "Preview below…" (preview was above) | Rewritten in plain words (EN/ES/VI drafts; baseline re-recorded) |

Still open from these walk-throughs (content, not structure): eight "Next step" taps before the first decision in the
freeze scenario; engine wording such as "continuity-planning gap", "confirmed compatible backup", "storage target, not a
drinking prescription"; the final step being the pets footnote after "72 hours: end of the exercise"; unformatted phone
numbers; "Choose above" wrapping in the bottom bar at default text size. Evidence: DemoJourneyUITests 8/8 and
DryRunTests 42/42 (iPhone 18 Pro), core `swift test` 320/51 suites, public-api locale drift tests 68/68, three
device-interaction walk-throughs on iPhone 17e. VoiceOver, Reduce Motion, iPad and physical-device checks of these
screens are not yet done.

## Native simulator audit — October 18 (Claude)

Structure after this pass (each primary editor is at most one transition from its tab root):

| Tab | Root shows | Direct entries |
|---|---|---|
| Prepare | Household, example badge, "Do next (n)" with the top item emphasized and two more, then tiles | Each task row → its focused editor (meetup → map set to that purpose, no nested stack); Your family; Your home; Family emergency card |
| Rehearse | Home diagram, fire/tornado/flood first, all six hazards | Scenario → scene first, "Step k of n" key moments, what changed this step, one decision, Debrief → comparison pushed in the same sheet |
| Plan | Living card summary with missing items, two fixed meetup slots, contacts, static map preview, home diagram | Card; meetup slot → map with purpose (save returns to Plan); Add contact; Home address; Open map; one Share / Print sheet whose preview is pushed inside it |

Removed: ShareWithFamilyView (third share path), the duplicate onboarding save button, the stacked Back/Cancel/Save
in pushed editors, the panning map inside the scrolling Plan page, and the exercise clock (replaced by step counts).
Verified by the DemoJourneyUITests and the screenshot tours listed in VERIFICATION. Not verified: VoiceOver order
walk-through, Reduce Motion, iPad, and anything on a physical device.


**Current native status: authored and source-reviewed; not simulator/device verified.** October 14 screenshots
and UI passes are historical evidence only. New journeys and screenshot tours target three destinations.
No timing, VoiceOver, real Maps, camera, Print, or share-lifecycle claim is established by this Linux pass.

| Entry/control | Implemented behavior | Evidence / native gate |
|---|---|---|
| Onboarding create / Finish later | One self, optional address, no required camera/GPS/medical profile or geometry | Core/vault migration tests; new no-layout journey unrun |
| Example household | Explicit fictional path, badges in preparation/home/rehearsal/export | Source review; visual badge consistency needs current screenshots |
| Prepare | First recommendation prominent, next two priorities, unresolved count, all preparations | Source review; small-screen/hierarchy check pending |
| Your family / contacts / supplies | Shared focused editor, save then dismiss, failures retain draft | Native AppPersistenceTests authored; UI tests unrun |
| Your home | Navigation from Prepare; manual/scanned layout, contextual shape/opening/landing correction, explicit levels, review and resident assignment | Core confirmation/routing tests; native canvas and LiDAR gate |
| Preparation row | Relevant factual editor; no generic completion certification | Subject/fingerprint tests; inspect each task's return path on simulator |
| Family emergency card | Universal selected-content preview; structured phone call actions | Core selected-content tests; native preview/share/print pending |
| Rehearse | Six hazards, visible home at start, stage/person selector, current-route state | Core deterministic fixtures; actual scene/gesture/AX checks pending |
| Rehearsal comparison | One hypothetical change, actual records untouched | Core counterfactual tests; current comparison navigation check pending |
| Plan | Live card, home and neighborhood previews; contacts/destinations; optional scenario export | Core plan/place tests; native PDF/snapshot inspect pending |
| Address | Apple autocomplete/manual/pin correction; correction versus moving | Native adapter/source review; real Apple resolution pending |
| Map | Persistent home/places, nearby suggestions, equivalent list, origin/mode choice | Fake cancellation tests authored; Apple failures/offline pending |
| Settings toolbar | Language, privacy/capability status, opt-in one-time local review reminder, destructive delete confirmation | Source review; EN/ES/VI control and destructive lifecycle checks pending |
| PDF activity/Print | Protected file leases until activity completion; same preview bytes | Source review; system activity/print/background test pending |

`DemoJourneyUITests` now covers skip-layout/contact/card preview, absent-layout home path, direct family/plan,
three spatial start scenes and supported-locale card access. `ScreenshotTourUITests` opens Home from Prepare and
Maps/address from Plan rather than relying on removed tabs. Both are authored, unrun. See the native handoff.

Accessibility requirements still to execute: small iPhone and large Dynamic Type; VoiceOver order and every
canvas/map text alternative; static Reduce Motion; non-color current/blocked/unknown distinctions; dark/light
contrast; long names/notes and translated pickers. The app keeps minimum target iOS 18. No language beyond the
existing English/Spanish/Vietnamese packs was added. Draft translations need human review even when keys resolve.

Follow-up source review removed the Prepare → Home sheet nesting; Home is a navigation destination with a focused
editor sheet. Primary preparation tasks still open their subject's relevant editor directly. Room selection resets
contextual state, and an outside-wall correction requires a new explicit choice. Home mode labels, validation
issues, confirmation questions, connection/floor summaries and reminder controls use EN/ES/VI keys. All issue and
question enums have locale-resolution coverage; native text layout/VoiceOver usability remain unverified.
Solo card review does not appear as joint family review; changing an item's location clears its old physical checks.

Latest independent source review led to fixes for location saves erasing ownership, duplicate-looking medical
subjects, permanent preparation loops, unreachable Reopen, broad Add contact forms, old-sensitive-export fallback,
route requests outliving selected destinations, missing scene-floor selection, invalid exit styling, missing
no-route occupant markers, scan-review dismissal and mismatched highlights. Typed focused editors and exact
subject captions now connect those facts to current tasks/cards. These are source/core findings, not observed
native usability results. The 42 native tests and current tours remain unrun; no screenshot-based review is claimed.

The selected-language follow-up closes source-level picker values, marker defaults, Help controls/statuses, phone actions, scan coaching, exercise clock/plurals, route facts, validation messages and export dates/decimals/provenance. All offered packs pass structural completeness, but ES/VI remain drafts. Official English resource text is identified; unknown SDK diagnostics and personal notes stay unchanged. Country water units now agree across the focused editor, tasks, rehearsal quantities/events/comparison and plan. New EN/ES/VI portable card/full-plan references were inspected as recorded in output/README; they do not verify native phone layouts. Seven app presentation-helper tests ran in a Linux harness, not an iOS test host.

## Final connected-flow source review

Prepare now lists recorded factual preparations for review/edit, separately from unresolved priorities. All
six rehearsals can start without geometry; the unavailable spatial state is explicit. Selected Plan preview
and Share/Print generate the same persisted document, lock selections during preparation and reject stale async
map results. The family card precedes diagrams in the selected phone document. Letter/A4 choice reaches sharing
from that preview. Home panels retain current affected/exposed rooms, start markers and no-route explanations.

Independent AI review found local-meetup migration/canvas-edit feedback and default-label localization defects;
regressions and fixes were integrated before the final portable run. Portable PDF inspection also found room
names could be covered by furniture fills; label drawing was moved after furniture in reference/native output.
These are source/reference-artifact findings; actual native views and accessibility remain unrun.

## Owner-directed Claude continuation

Read the full original goal and CLAUDE_CONTINUE_PROMPT. Do not infer completion from this table. Claude is to
use ideators and inspect actual UI/PDFs, independently review the rehearsal changes, remove nested sheets,
wizard detours and hidden actions, and improve strong clean map/home/icon visual communication without new
feature bloat. Latest source fixes add direct confirmed person/equipment deletion, matching neighborhood/inset
panels and endpoint route invalidation. These have portable/source evidence only. The latest hosted native
build is failing at MapKitAdapters:193; no current phone screenshots or native usability result exists.
