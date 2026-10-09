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

## Actions (`content/actions/actions.json`, 22 actions)

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

Not modeled and never displayed: fire spread, smoke tenability or concentrations, CO concentrations, structural
failure, injury or survival probability, indoor temperature forecasts, medical safety deadlines, "safest real-time
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

`content/sources/sources.json` lists S01–S31 with publisher, URL, check date, and review state. Regional directory
entries and which were verified against official pages are recorded in `docs/lanes/agent-c.md`.
