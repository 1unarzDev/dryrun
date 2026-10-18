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
| Your home | Manual/scanned layout, contextual correction and resident assignment | Core confirmation/routing tests; native canvas and LiDAR gate |
| Preparation row | Relevant factual editor; no generic completion certification | Subject/fingerprint tests; inspect each task's return path on simulator |
| Family emergency card | Universal selected-content preview; structured phone call actions | Core selected-content tests; native preview/share/print pending |
| Rehearse | Six hazards, visible home at start, stage/person selector, current-route state | Core deterministic fixtures; actual scene/gesture/AX checks pending |
| Rehearsal comparison | One hypothetical change, actual records untouched | Core counterfactual tests; current comparison navigation check pending |
| Plan | Live card, home and neighborhood previews; contacts/destinations; optional scenario export | Core plan/place tests; native PDF/snapshot inspect pending |
| Address | Apple autocomplete/manual/pin correction; correction versus moving | Native adapter/source review; real Apple resolution pending |
| Map | Persistent home/places, nearby suggestions, equivalent list, origin/mode choice | Fake cancellation tests authored; Apple failures/offline pending |
| Settings toolbar | Language, privacy/capability status, destructive delete confirmation | Source review; EN/ES/VI control and destructive lifecycle checks pending |
| PDF activity/Print | Protected file leases until activity completion; same preview bytes | Source review; system activity/print/background test pending |

`DemoJourneyUITests` now covers skip-layout/contact/card preview, absent-layout home path, direct family/plan,
three spatial start scenes and supported-locale card access. `ScreenshotTourUITests` opens Home from Prepare and
Maps/address from Plan rather than relying on removed tabs. Both are authored, unrun. See the native handoff.

Accessibility requirements still to execute: small iPhone and large Dynamic Type; VoiceOver order and every
canvas/map text alternative; static Reduce Motion; non-color current/blocked/unknown distinctions; dark/light
contrast; long names/notes and translated pickers. The app keeps minimum target iOS 18. No language beyond the
existing English/Spanish/Vietnamese packs was added. Draft translations need human review even when keys resolve.
