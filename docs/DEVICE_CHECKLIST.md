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
A6 Settings delete-all confirms; relaunch remains onboarding:

B. Native LiDAR (network/location/intelligence independent)
B1 Camera requested only when scan chosen; support check accurate; denial retains manual path:
B2 Guidance -> first room -> continue connected room in shared frame -> process:
B3 Compare walls, surface categories, parent/opening matching, scale, orientation to measurements:
B4 Correct room/type/opening on highlighted canvas; width/operability survive connection edits:
B5 Confirm actual grade (above/below/ground/walkout), discharge and stairs/landings; unknown blocks:
B6 Window inventory alone never becomes escape; mobility/grade/access checks enforced:
B7 Assign occupant, save, force-quit/relaunch; same canonical home and assignments retained:
B8 Rehearse fire/flood/tornado; export qualified current routes/diagram; no superseded route:
B9 Rescan same home retains address/meetups/home ID; ambiguous room assignments surfaced:
B10 Cancel/restart + late room/builder callback; repeated Finish; no stale publication:
B11 Background during camera request, scanning AND structure processing; retained draft/retry:
B12 Poor tracking/processing failure; valid completed groups retained; unrelated frames not merged:
B13 Upstairs-only/basement-only scan does not infer ground; split/walkout and offset landing review:
B14 Unsupported non-LiDAR device and denied camera -> usable manual/example paths:

C. Maps, share and offline
C1 GPS denied, typed home address still plans; automatic nearby discovery cancel/retry:
C2 Near and backup meetup survive sheets/relaunch, every edit updates card and next PDF:
C3 Unknown/non-US address has no Texas public request or assumed local emergency number:
C4 Airplane mode: contacts, saved place text, home, retained plan work; live map/search honest:
C5 Share activity keeps protected file until completion/cancel, then purges (also background):
C6 Print preview Letter/A4/grayscale; print completion/cancel releases export lease:
C7 Map snapshot failure still exports readable text/home/card, essential meetup/phone details:
C8 No private household/contact/medical/scan fields in public request/diagnostic traffic:

D. Presentation/accessibility
D1 Small phone and large Dynamic Type: no hidden primary control, clipped data or collisions:
D2 VoiceOver can create/contact/card/rehearse/choose place; meaningful list/route alternatives:
D3 Reduce Motion: equivalent static hazard scene; light/dark/non-color statuses readable:
D4 EN/ES/VI selected values/errors/unit/labels and diacritics; no silent critical translation:
D5 Very long individual note ends correctly after continuation, large family all listed:
D6 Time to first useful card / rehearsal duration (record observed seconds; no target claims):
```

A successful source parse or simulator render does not satisfy B. Report exact device/OS/SHA and incomplete
paths. An approved physical test validates this implementation's observed behavior, not real disaster safety.
