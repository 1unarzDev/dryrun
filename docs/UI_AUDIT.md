# UI audit — October 17 revision

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
native usability results. The 33 native tests and current tours remain unrun; no screenshot-based review is claimed.

The selected-language follow-up closes source-level picker values, marker defaults, Help controls/statuses, phone actions, scan coaching, exercise clock/plurals, route facts, validation messages and export dates/decimals/provenance. All offered packs pass structural completeness, but ES/VI remain drafts. Official English resource text is identified; unknown SDK diagnostics and personal notes stay unchanged. Country water units now agree across the focused editor, tasks, rehearsal quantities/events/comparison and plan. New EN/ES/VI portable card/full-plan references were inspected as recorded in output/README; they do not verify native phone layouts. Seven app presentation-helper tests ran in a Linux harness, not an iOS test host.
