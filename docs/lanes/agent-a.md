# Agent A lane — simulation, scenarios, ranking, counterfactuals

Status vocabulary: TESTED_CORE = Swift Testing on Linux (swift:6.2 Docker). Nothing in this lane has run on iOS.

## Implemented

| Area | Files | Status |
|---|---|---|
| Scenario pack schema + loader/validator (`ScenarioLibrary.load(from:)`; rejects unknown rule IDs, non-fictional packs, missing/unsafe default options) | `Simulation/ScenarioDefinition.swift` | TESTED_CORE |
| Dependency model (graph #1) with AND/OR requirements, bounded fixed point, hard `nonConvergent` error | `Simulation/DependencyModel.swift` | TESTED_CORE |
| Backup allocation: per-source output limit allocated once in load-ID order; energy drain only when every draw is known; grid-tied solar, unconfirmed islanding, generator without confirmed ≥20 ft outdoor placement, unconfirmed setup never supply a load | `Simulation/BackupAllocation.swift` | TESTED_CORE |
| Discrete-event engine (`RehearsalEngine.run`, `.compare`): order = minute, priority, ID; depletion events computed from current draw; derived service-change events with `EvidenceLink` (rule, fact IDs, cause event, sources); snapshots; unknowns; unmet requirements | `Simulation/RehearsalEngine.swift` | TESTED_CORE |
| Rule semantics: external set, water advisories (5 distinct types), checkpoints (CDC storage target), power restoration (no refill / advisory persists / device check), displacement, fire routes via injected `EgressPlanning`, tornado (shelter, manufactured home, night alerting), flood (no crossings, well quality), choice effects | `Simulation/HazardRules.swift` | TESTED_CORE |
| Interventions on simulation copies (hypothetical values use `origin: .scenarioAssumption`) | `Simulation/Interventions.swift` | TESTED_CORE |
| Action catalog (22 actions) + deterministic triggers + lexicographic ranker + structured diff | `Ranking/ActionCatalog.swift`, `Ranking/RecommendationRanker.swift` | TESTED_CORE |
| Six packs, all `reviewStatus: draft`, all fictional | `content/scenarios/*.json` | TESTED_CORE (behaviour), content NOT reviewed |
| English text for every emittable key (308 scenario/service/reason keys, 73 action keys) | `content/locales/en/{scenarios,actions}.json` | key coverage TESTED_CORE; wording NOT reviewed |
| Action catalog file generated from Swift | `content/actions/actions.json` | TESTED_CORE (file == `ActionCatalog.builtIn`) |
| Expected-outcome fixtures (freeze/oak baseline; freeze/oak + backup comparison) | `fixtures/scenarios/*.expected.json` | TESTED_CORE |

## Tests (all passing)

Lane run (`--filter "Simulation|Ranking|Counterfactual|Rendered"`): `Test run with 35 tests in 5 suites passed` (plus a disabled exploration dump, `DRYRUN_EXPLORE=1`).
Whole package at hand-off: 89 tests, 80+ passing; the only failures are the lead's ES/VI placeholder-parity test, because English
templates changed after the Spanish draft was translated (see "Translation follow-up" below).
Regenerate fixtures/catalog only after reviewing a behaviour change: `DRYRUN_WRITE_FIXTURES=1`.

Section 18 SIMULATION coverage: determinism incl. equal-time ordering; compatible vs unknown/incompatible backup; shared
output/energy never double-allocated or negative; well vs municipal; restoration limits; unknown runtime → verification action;
chemical advisories never recommend boiling (and boil needs power); no-car relocation; handset/charging/Wi-Fi/cellular distinct and
a dead simulated phone does not end the exercise; counterfactual isolation; six scenarios distinct for each household. Extra: unsafe
options never default/recommended/rewarded; fire blocked-primary → alternative and both-blocked → typed no-route; tornado
manufactured home / no distant travel / night alerting; flood no-crossing; every modelable card changes its replay; every emitted key has English text.

## Design notes for the lead

- Service IDs added beyond the contract list: `svc.power.home`, `svc.alerts`, `svc.destination`, `svc.relocated`,
  `svc.water.municipal`, `svc.water.utilitySafety`, `svc.water.wellSafety`, `svc.wellPump.mechanical`, `svc.internet` (see `Svc`).
- Locale conventions the UI needs: derived events use `service.<svc-without-"svc.">.<state>` (devices: `service.device.*` with `{device}`);
  template value `reason` → localize via `reason.<code>`, `independence` → `independence.<status>`, `advisory` → `advisory.<type>`;
  effort and tier labels at `effort.<band>`, `tier.<n>`. `act.relocation.arrange` uses `whyKey` `action.act.relocation.arrange.why.{heat|cooling|displacement}`.
- Choice events have the option's label as `titleKey` and feedback as `detailKey`; event ID `evt.<choicePointID>`.
- `RehearsalResult.routes` holds usual routes (no exclusions) followed by post-blockage routes; distinguish by `request.exclusions`.
- Fire origin is authored by room kind (`kitchen`); if a home has no kitchen, origin falls back to the first person's usual exit room.
- `RehearsalEngine(library:planner:actions:)` — `actions` defaults to `.builtIn`. No Models changes outside `Rehearsal.swift` (none were needed there either).

## Lead review fixes (integration round)

- No raw IDs or enum codes in rendered text: exit routes use `{exitRoom}` (the room's household label); reason/independence/advisory
  codes stay in `templateValues` for machines but are surfaced only as `detailKey` = `reason.<code>` / `independence.<x>` / `advisory.<x>`.
  Enforced by the "Rendered English" test (renders every event/card for 3 households × 6 scenarios × variants).
- "Try this change" for `act.relocation.arrange` / `act.tornado.sturdy-building-plan` carries a choice override
  (`parameters[<choicePointID>] = <relocate option>`), so the replay actually takes the relocation branch (adds `relocation.done`,
  removes later depletion events). The baseline keeps its own choices. Ranking rules are unchanged (tier, then effort, breadth, ID).

## Translation follow-up (Agent C files, not edited by Agent A)

Placeholders changed in `es/scenarios.json` keys: `scenario.common.displacement.gap`, `scenario.common.recovery.advisory-remains`,
`scenario.common.relocation.blocked`, `scenario.home-fire.route.{alternative,no-usual,none,still-clear}`,
`scenario.tornado.night-alert-received`, `scenario.water-outage.boil.not-feasible`. New English keys to translate:
`scenario.common.checkpoint.water-target-unknown`, `scenario.tornado.night-alert-via.{phone,radio}`, `action.act.water.store-3day.why.unknown`
(es + vi). `vi/scenarios.json` did not exist at hand-off.

## Partial / known gaps

- All content is AI-drafted and `draft`; needs human/source review against S19–S26 before being presented as guidance.
- Pets' water needs, sanitation water, and food-storage timing are noted as unknowns/planning milestones, not modelled quantities.
- Indoor temperature, fire/smoke spread, CO, structural failure and injury are intentionally NOT modelled.
- Standby generators power home circuits with unknown runtime (fuel not modelled). Router-on-backup is a boolean fact, not an energy load.
- Handset model is a single household-level runtime assumption, not per-person phones.
- Tornado shelter check does not route inside the home (by design: no distant travel); multi-floor shelter access for step-free users is not checked yet.
- `seed` is carried and preserved but no authored randomness uses it yet.
