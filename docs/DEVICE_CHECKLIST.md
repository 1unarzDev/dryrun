# Physical-device checklist — current revision

**Unexecuted in this Linux pass.** Native build and device scan remain pending. First follow
CLAUDE_NATIVE_HANDOFF.md; install with:

```bash
DEVELOPMENT_TEAM=<TeamID> BUNDLE_ID=com.<unique>.dryrun scripts/mac/device.sh
```

Use fictional household entries; a consenting measured room may be scanned locally. Never send its private scan,
address, contacts, or photographs. Record PASS/FAIL/SKIP, observed error and reproduction for each item.

```text
Test date / build SHA (+ local changes):
Device model / OS / LiDAR capability:
Xcode / SDK / deployment target:
Installation method / signing result:

A. Fresh personal use, no prerequisites
A1 Skip address and scan; one self/unknown age; general preparations and universal card work:
A2 Add international phone contact and selected critical note; card preview/share/Print match:
A3 Force-quit/relaunch; household, contacts and intentional absent geometry retained:
A4 Device lock/unlock and background privacy cover (also while PDF open):
A5 Failed save retains draft and does not publish/completion-report success:
A6 Settings delete-all confirms; relaunch remains onboarding; failed deletion retains existing data/reminder:
A7 Opening review/Settings asks no notification permission; explicit reminder button requests it once:
A8 Deny reminder permission, retained draft/existing reminder; schedule/relaunch/deliver/cancel one local reminder:
A9 Delete while permission/add is suspended; no late reminder survives; no household fields in notification:
A10 Solo card review and joint review independent; change alarm location -> check/coverage reopen, notes preserve:

A11 Quantity/location and subject-specific medical preparation save-return, relaunch and exact Undo/reopen:
A12 Physical drill separate from exit check; utility number does not complete trusted contact:

B. Native LiDAR (network/location/intelligence independent)
B1 Camera requested only when scan chosen; support check accurate; denial retains manual path:
B2 Guidance -> first room -> continue connected room in shared frame -> process:
B3 Compare walls, surface categories, parent/opening matching, scale, orientation to measurements:
B4 Correct room/type/opening on highlighted canvas; width/operability survive connection edits:
B5 Confirm actual grade (above/below/ground/walkout), discharge and stairs/landings; unknown blocks:
B6 Window inventory/legacy Boolean alone never authorizes escape; person-specific mobility/grade/access checks enforced:
B7 Assign occupant, save, force-quit/relaunch; same canonical home and assignments retained:
B8 Rehearse fire/flood/tornado; export qualified current routes/diagram; no superseded route:
B9 Rescan retains address/meetups/home ID; unrelated ordinal room IDs clear, supported capture lineage remaps:
B10 Cancel/restart + late room/builder callback; repeated Finish; no stale publication:
B11 Background during camera request, scanning AND structure processing; retained draft/retry:
B12 Poor tracking/processing failure; valid completed groups retained; unrelated frames not merged:
B13 Upstairs-only/basement-only scan does not infer ground; split/walkout and offset landing review:
B14 Unsupported non-LiDAR device and denied camera -> usable manual/example paths:
B15 Resize/move a room: first capture retained, unrelated captured wall stays, no route until room/doors reviewed:
B16 Add/remove a room after correction: no missing/phantom outline walls; select another opening resets wall choice:
B17 Explicit new level/first room/stairs: separately positioned landings, invalid/same-floor/stair-free mobility refused:
B18 Change shelter grade/add lower floor/window: old shelter rejected by both current scene and planner; re-review:

B19 Selected floor/person agrees in 2D/3D/list; exposed/no-route start room still named:
B20 Balcony/blocked/inoperable opening unavailable; annotation/shelter/two stair endpoint highlight correct:
B21 Process earlier valid groups after interruption: active callback cannot enter frozen group; failure retains draft:
B22 Helper reach cannot cross walls/blocked spaces/narrow openings or incompatible stairs:
B23 No-layout six hazards work without routes/scenes; leak and regional flood have distinct instructions:
B24 Selected preview/export retains practiced origin/starts/choices; current exclusions and primary/alternative styles agree:

C. Maps, share and offline
C1 GPS denied, typed home address still plans; automatic nearby discovery cancel/retry:
C2 Near and backup meetup survive sheets/relaunch, every edit updates card and next PDF:
C3 Unknown/non-US address has no Texas public request or assumed local emergency number:
C4 Airplane mode: contacts, saved place text, home, retained plan work; live map/search honest:
C5 Share activity keeps protected file until completion/cancel, then purges (also background):
C6 Print preview Letter/A4/grayscale; print completion/cancel releases export lease:
C7 Map snapshot failure still exports readable text/home/card, essential meetup/phone details:
C8 No private household/contact/medical/scan fields in public request/diagnostic traffic:

C9 Select/dismiss/change destination while GPS/directions pending; no late route or stuck loading:
C10 Failed fresh selected export never shares older sensitive document; medical locations follow selection:
C11 No-op/unit-only address keeps coverage; changed geography invalidates it without resetting family:
C12 Legacy named indoor meetup appears on card, remains editable/deletable without being recreated:
C13 Official text-only resource opens save/contact/details; source metadata survives save/relaunch:
C14 Near/backup meetup pins survive optional-resource caps; map and text numbering agree:

D. Presentation/accessibility
D1 Small phone and large Dynamic Type: no hidden primary control, clipped data or collisions:
D2 VoiceOver can create/contact/card/rehearse/choose place; meaningful list/route alternatives:
D3 Reduce Motion: equivalent static hazard scene; light/dark/non-color statuses readable:
D4 EN/ES/VI selected values/errors/unit/labels and diacritics; no silent critical translation:
D5 Very long responder note follows the main contact/meetup card without rewriting; END retained, large family all listed:
D6 Time to first useful card / rehearsal duration (record observed seconds; no target claims):
D7 US/FR/VN/unknown water units agree in task/editor/event/comparison/plan; US/CA local numbers sourced, no foreign default 911:
D8 Card date/timezone/decimal and fallback/source labels correct; user notes unchanged:
```

A successful source parse or simulator render does not satisfy B. Report exact device/OS/SHA and incomplete
paths. An approved physical test validates this implementation's observed behavior, not real disaster safety.

## Owner-confirmed Mac/device handoff

The owner confirmed the existing Claude/Mac checkout will have a connected LiDAR-capable iPhone Pro and an
Xcode signing account. Model/OS/signing/install success are not yet recorded. First reconcile local work and
fix the current native SDK build failure in VERIFICATION, then run scripts/mac/verify.sh. Only after a
successful target build, use `scripts/mac/device.sh --list` and
`DEVELOPMENT_TEAM=<TeamID> BUNDLE_ID=com.<unique>.dryrun scripts/mac/device.sh --device <UDID>`.
No Expo Go server runs this native SwiftUI/RoomPlan app. Read CLAUDE_CONTINUE_PROMPT and the complete original
goal; do not accept this checklist's existence as device verification. Record actual model/OS/commit,
connected-room scan/correction/grade/occupant assignment/save/relaunch/rehearsal/export and interruption paths.
Keep private real-home geometry local and use fictional evidence for anything committed/shared.
