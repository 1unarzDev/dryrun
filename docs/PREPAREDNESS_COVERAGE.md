# Household preparedness coverage

October 17 revision. These are records of preparation, never a safety score or certification. `BaselinePreparedness` evaluates recorded facts without requiring geometry or rehearsal. Rehearsal recommendations add scenario context; subject-specific needs use `actionID|person/device/backup ID`. The stable order is essential gap, blocking unknown, supplies/continuity, cross-hazard mitigation, maintenance/practice; effort and breadth break ties only within a tier. Exact IDs break remaining ties.

| Preparation | Applicable input / completion | Direct editor | Scenario / source |
|---|---|---|---|
| Smoke alarms | Available, recorded location, separate household coverage review and physical functional-check date | Check record | Fire / S19 |
| CO alarms | Household alarm review applies regardless of heating-fuel answer (cooking/garages/other sources may be unknown); available, location, separate coverage review and functional check | Check record | Fire/power loss / S20 |
| Extinguisher | Available, accessible location, user-recorded check; separate family location-awareness record | Check record | Fire / S53 |
| Clear exits / second way | Actual physical check and recorded locations; cannot create a supported route or usable window | Home/check record | Fire / S19 |
| Stored water | Canonical US gallons (editor shows litres outside explicitly known US homes) and a recorded storage location versus 3-day household-count storage planning target, with litre equivalent; not a clinical intake prescription | Supplies | Continuity / S26 |
| Food / first aid / flashlight / batteries / sanitation | Available plus location; special dietary/infant requirements in household-authored notes | Supplies/check record | All / S53 |
| Alert reception / local enrollment | Radio ownership or an explicit alternate reception plan plus finding/access instructions; local enrollment only within supported coverage and with an actual recorded channel | Reception/enrollment record | Tornado/continuity / S52,S53 |
| Essential medicine availability | Only recorded essential medicine needs; per-person record (or unassigned medicine equipment), availability and location independent of storage/power | Exact subject checklist | Continuity / S54 |
| Essential equipment supplies | Applicable non-medicine essential equipment, per-device availability and location | Exact device checklist | Continuity / S25 |
| Physical fire drill | Explicit real drill, recorded plan/participants and check date; separate from digital practice or clear-exit inspection | Drill record | Fire / S19 |
| Water utility / well-test planning | Municipal: named usable waterUtility phone contact. Private well: recorded testing-contact/instructions plan; no potable-water claim | Contact / well-plan record | Water/flood / S24 |
| Pet essentials | Applicable when pets recorded; supplies/location | Supplies | Relocation / S53 |
| Trusted/out-of-area contact | Structured name and usable recorded phone; a name alone is incomplete | Contacts | Reconnection / S52 |
| Near-home / backup meetup | Separate saved-place purposes, with readable label/address/instructions; indoor annotations alone do not substitute a geographic record | Shared place selector | Fire / displacement / S52 |
| Helpers | Relevant assistance need and explicit helper ID; no duty to re-enter danger | Family | Fire / relocation / S19 |
| No-car transport | No vehicle plus an agreed alternative | Household travel | Relocation / S52 |
| Essential power support | Exact device's confirmed compatible source, source setup check, documented runtime; ownership alone does not satisfy | Shared equipment/backup form | Outage / S25 |
| Cold medicine storage | Medicine-specific recorded instructions, explicit storage requirement/unknown, planned cold support; no invented storage limit | Shared medical form | Outage / S54 |
| Flood and heat/cold arrangements | Explicit recorded household plan/location, not an address-level hazard prediction | Preparation record | Flood / heat / cold / S23,S53 |
| Home/shelter geometry | Optional geometry for general use; spatial routes require reviewed relevant exits/grade/connections/shelter | Home review | Fire/flood/tornado / S19,S23,S22 |
| Review | Missing/stale family-card review and dated rechecks of completed alarm/supply facts appear in the maintenance tier; an explicit recorded review/check closes them | Card review/check record | Maintenance / S52,S53 |

Completion of factual baseline work follows the actual saved record. Generic Done does not certify equipment, escape, or shelter. Subject completion records require an unchanged subject fingerprint; legacy unscoped completions are never copied onto scoped needs. Reopening removes only that task record. Physical check records are editable and clearing the check reopens the missing-check task.

Maintenance accepts an injected reference date for reproducible checks. Completed alarms with a check older than 30 days get a review prompt; other completed, dated checklist items and the family-card review use a 180-day app planning cadence. The 180-day cadence is an interface prompt, not an authoritative storage limit, protection guarantee, or replacement for manufacturer/provider guidance. Missing essential protection retains its higher priority tier. Users record a fresh actual check or family-card/contact review; generic completion cannot hide it. No notifications are scheduled by default. The user may explicitly choose one non-repeating local review reminder in Settings or the review form.

Scope limitations: there is no inventory catalog, automatic whole-home alarm coverage analysis, prescription advice, clinical interruption time, or automatic emergency response. Source wording remains prototype content pending human safety/language review; automated tests validate data semantics, not household safety.

## Verification and remaining product boundaries

The preparation lane ran focused portable core tests (final integrated counts in VERIFICATION) (family-card selection, legacy/default/custom labels, refrigeration-only and mixed support, contacts, subject identity/completion invalidation, baseline/derived merging, ranking and English rendering) and parsed its changed Swift files on Linux. This does not establish native SwiftUI type correctness or simulator/device usability. No physical household review or consenting-test feedback was invented.

The current focused checklist uses optional user-authored notes for dietary/infant, reconnect, flood and heat/cold arrangements; it does not yet supply a tailored hazard questionnaire for each. Alarm presence/location, household coverage review and functional-check records are separate structured facts; the app does not automatically certify whole-home coverage. Reminders are optional, generic local notifications; system authorization, delivery and deletion behavior remain native test gates. EN/ES/VI app-authored preparation controls are supplied as draft translations; human review, actual VoiceOver/large Dynamic Type forms, international address examples and native exported PDF inspection remain required. Exact unresolved cross-lane map/plan issues are recorded separately in the integration review; portable core tests do not validate Apple requests, attribution, sharesheet lifecycle or native layouts.

Focused task routing uses PreparationEditTarget and exact subject IDs. Medication/device-supply tasks keep
person/device captions in the list and editor. PreparationDraft synchronizes only deliberately changed ownership
answers, so adding a location/contact cannot replace a known supply answer with unknown. The card uses the same
recordedSupplyAvailability rules as baseline evaluation. Medication locations follow Medication selection;
equipment-supply locations follow Critical information selection. Neither depends on generic private notes.
