# Safety, sources, and content review state

**Review state: every scenario pack, action, and locale string is AI-drafted and `draft`.** No qualified human has
reviewed the safety wording or the translations. Authoritative sources validate guidance wording, not this
simulation's implementation. Plans print "Prototype safety content - expert review pending"; ES/VI plans also print
"Draft translation - language review pending".

## Scenario packs (`content/scenarios/*.json`, version 1.0.0, status draft)

| Scenario | Sources | Distinct modeled behavior | Decisions |
|---|---|---|---|
| Freeze with power loss | S20, S25, S26 | Grid loss → only loads with confirmed compatible backup keep running; electric heat / heat with powered controls stops; electric well pump stops while stored water is tracked separately; router/Wi-Fi vs cellular vs handset charge separate; essential device continuity gap; restoration does not refill water/batteries or certify devices; pipe check | Warm-up choice (unsafe oven/stove and garage generator options are never rewarded); stay or relocate |
| Heat wave with grid strain | S20, S21, S25 | Grid *strain* (power still on, conservation) distinct from an authored rotating outage; loss of cooling access; refrigerated medication gap; cooled destination + transport | Plan for the hottest hours (fan-only is not rewarded); wait or go during the outage |
| Tornado | S20, S22, S29 | Pre-warning preparation, warning received (night variant depends on phone/radio alerts), preselected shelter spot (not an engineered safe room), manufactured-home limitation (plan a sturdy building in advance), no routing to a distant shelter during a warning | Shelter action; recovery |
| Flash flood | S18, S20, S23, S24, S29 | Early relocation, official instruction, roads/crossings closed, no-car path, never a route through water or around barricades; flood map is context only | Leave early vs wait; driving through water is never rewarded |
| Home fire | S19, S27, S29 | Authored origin and blocked spaces; per-person practice routes from the real egress planner; blocked primary → modeled alternative or typed no-route; helpers never re-enter; displacement recovery | First move (belongings, pet search, fighting the fire, hydrant are never rewarded); after escaping (re-entry never rewarded) |
| Water outage | S20, S24, S26 | Distinguishes quantity unavailable, unknown quality, boil, do-not-drink, do-not-use; never recommends boiling for chemical advisories; boil feasibility depends on power/fuel; stored water allocated by planning need | One decision point plus advisory variants (**gap:** brief asks for "a few" decisions) |

Rule semantics live in Swift (`Simulation/HazardRules.swift`, `DependencyModel.swift`); packs supply timing, choices,
exclusions, advisories, and text keys only. See `docs/lanes/agent-a.md` for rule-by-rule detail.

## Actions and baseline preparedness

Ranked lexicographically: (1) unmet essential power/assistance/exit/shelter requirement, (2) unknown fact that blocks
dependable preparation, (3) scenario supply/continuity gap, (4) multi-scenario preparation, (5) general; ties broken by
cost band, then number of scenarios helped, then ID. Cost never outranks a critical dependency. No-cost actions are
included (meeting point, helper assignment, alert enrollment, practice drill, utility contact).

## Uncertainty handling (enforced in code and tests)

- `EvidenceValue` carries origin/status; only *confirmed* values satisfy hard requirements. Unknown ≠ no ≠ zero.
- Unknown device runtime stays unknown and generates a verification action; no patient interruption window is ever estimated.
- Phone runtime is an explicit exercise assumption (`.assumed`, 18 h), not a measurement.
- Water uses the CDC **storage target** (1 gal/person/day × 3 days), labeled as such; pets' extra water is noted, not quantified.
- Routes are "practice routes under these assumptions"; scanned doors/clearances are proposals until confirmed.

## Claims explicitly excluded

Authored, topology-aware fire/smoke, indoor-water and window-exposure visuals are educational exercise states;
they do not simulate physical fire dynamics, hydraulic forecasts or structural failure. They share the deterministic
routing exclusions and never determine route validity from pixels. Not modeled: smoke tenability/concentrations,
CO concentrations, injury or survival probability, indoor temperature forecasts, medical safety deadlines, "safest real-time
route", seconds-to-escape countdowns, engineered tornado-shelter certification, current flood depth at the home,
road safety from map data, readiness percentages or survival scores, lives or money saved.

## Localization review state

| Locale | Domains | State |
|---|---|---|
| en | common, plan, help, scenarios, actions | AI-authored source text; safety review pending (manifest note) |
| es | per `content/locales/manifest.json` | AI draft; language review pending |
| vi | per `content/locales/manifest.json` | AI draft; language review pending; missing domains fall back visibly to English |

Fallback is never silent: each resolved string reports its locale; plans print a fallback note and mark English
lines "[EN]"; public-directory data (English source text) is marked as English inside translated plans.

## Sources

`content/sources/sources.json` lists source IDs including the October 17 additions S52–S55 with publisher, URL, check date, and review state. Regional directory
entries and which were verified against official pages are recorded in `docs/lanes/agent-c.md`.

## October 17 changes

The family card is household-level and optional clinical selections are explicit. Empty fields say not provided,
not no conditions. Contacts use stored structured numbers; unknown foreign location gets no Texas contacts or
assumed emergency number. Core/general planning has no supported-county prerequisite.

Electrical equipment and medicine cold storage have distinct requirements (both may apply). Refrigerator
instructions, compatibility, setup and duration must be supplied/confirmed by the household or provider; no
patient-safe interruption or medicine-storage limit is inferred. Adding a backup establishes ownership only.

Baseline coverage, inputs, direct editors, completion and citations are in PREPAREDNESS_COVERAGE. Alarm presence,
location and physical functional check are distinct; a confirmed marker does not establish coverage/test success.
Priority uses one deterministic lexicographic order; effort never outranks an essential dependency. Subject IDs
and relevant fingerprints prevent one person's/device's completion from applying to another. A hypothetical
comparison never changes factual preparation records.

Confirmed destinations/grade/access are routing gates. Window inventory does not certify escape; exposed start
rooms remain affected. Flood exercise assumptions are separate from regional flood forecasts; higher refuge is
not a universal evacuation instruction. Tornado shelter is a household-confirmed planning choice, never an
engineered safe-room/building certification. No helper re-entry is modeled as a successful rescue route.

References S52 Red Cross family planning, S53 Red Cross fire preparedness, S54 FDA medicine guidance, S55 NWS
flood safety were fetched successfully in this pass. Fetching sources is not professional safety review. EN/ES/VI
native/spatial additions remain AI drafts, including untranslated source titles and user-authored notes retained
verbatim. All safety wording and translations need qualified human review; no participants or endorsements exist.


Follow-up review fixes retain unrelated captured barriers during room correction, exclude corrected rooms until
explicit review, and use one current shelter suitability contract across confirmation, routing and simulation.
A recorded window contradicts a no-window shelter candidate even if it is rejected as an escape option. Adding a
lower level or changing grade cannot leave a historical marker sufficient for a shelter route. A hypothetical
comparison edits only its copied inputs.

Heating fuel alone does not remove the CO-alarm review: other combustion sources or garage exposure may be unknown.
Physical check/coverage/awareness evidence is invalidated when the described item's availability/location changes.
Monthly alarm review and the app's 180-day other/card maintenance cadence are prompts, never protection guarantees
or medicine-storage advice. Users may explicitly schedule one generic, non-repeating local review reminder; the app
never starts a default notification campaign. Native delivery/cancellation/deletion still require testing.

Latest baseline records distinguish essential medicine availability, equipment supplies, cold storage and direct
power support per exact subject. Selected card content follows those same boundaries. A utility number does not
substitute a trusted family contact. A physical drill is separately dated; flood/well testing arrangements are
preparations, never a supported refuge/route, completed evacuation, safe drinking-water test or protection score.
Location-only edits preserve known ownership. Rendering unavailable/balcony/blocked openings as ordinary exits
was removed using shared presentation semantics; route decisions still belong to the deterministic planner.
New EN/ES/VI prose remains AI draft content with existing source/review status.

Selected-language follow-up removes unconditional 911/211 Texas wording from fire rehearsal content. Rehearsals refer to local emergency services; plan instructions use 911 only with explicit US/CA metadata. The official Government of Canada health-care page was fetched successfully and its emergency-services transcript checked; new S56 records that scope and remains needsReview. CRTC/911.gov fetches were denied and other candidate URLs failed; no successful review is claimed for them. No new public backend country coverage was added.

Water is a CDC storage planning target, not a clinical prescription. Only displayed quantities convert from canonical US gallons to litres outside US; storage facts and simulation outcomes do not change. Card translation provenance and source lists now include composed labels and long-note continuation without altering user-authored instructions. All new translation/safety wording remains AI draft content pending human review.

The independent follow-up source review found four further issues and fixes: empty default event subjects now resolve by longest exact evidence ID (including dotted IDs), mixed power/cold-storage card wording no longer denies electrical requirements, composed water-unit fallbacks reach document provenance, and official English alert text has a fallback label. Core regressions cover subject/default/custom-name retention, route reasons, unit fallback and mixed card sections; native interaction remains pending.

## Shared support and spatial semantics

A backup source can be owned/assigned yet remain unavailable: recorded setup, generator placement or solar
islanding where applicable, output/shared-load constraints, compatibility and positive user-documented runtime
remain separate gates. Unknown-first sharing cannot bypass a source's capacity check for a second device.
Cold-only medication notes survive intentionally selected export without requiring electrical runtime.
Wheelchair transport and separate alarm presence/location/coverage/functional-check facts reach both tasks and
rehearsal. A confirmed alarm marker alone never certifies function or coverage, including without a layout.

A local leak no longer borrows regional flood road, well/outage/displacement or higher-refuge assumptions;
regional flooding retains early official action and no water/road safety certification. No-layout exercises
produce no spatial guidance. Legacy window suitability alone cannot authorize a person's escape; helper reach
uses actual portal/geometry/mobility validation. Qualified diagrams include current exclusions and no-route
starts, never historical routes presented as available. EN/ES/VI additions remain AI drafts awaiting review.

## Visual refinement boundary for the next pass

Claude owns the owner-requested visual refinement; see the original goal and CLAUDE_CONTINUE_PROMPT.
Strong maps, home plans and icons must keep source/evidence/unknown states and route qualifications legible.
Visual hazard animation is an illustrative authored exercise, never the routing authority or a prediction.
Confirmed continuity destinations now export with household-recorded/recheck wording; a public-site record
still does not confirm activation, capacity or access. Saved map-resource contact/source/check details survive
into plan text. New EN/ES/VI strings and content2026.10.2 remain AI drafts; no professional safety or language
review occurred. Actual native PDFs, system lifecycle and physical capture remain unverified.
