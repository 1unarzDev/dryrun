# Scenario/learning specialist work order and integration report

Owner: `scenario_learning`; base `26332de`; requirements HAZ-01..06, DEMO-01, REL-01, REVIEW-01. Scope: core Session/Simulation plus new deterministic tests. No app/shared model/assessment edits or device access.

Purpose: help each family make a feasible next decision, observe its actual modeled consequence and practice the remaining gap in the existing rehearsal. Prefer the current scene/decision/debrief flow over new navigation. Inputs are authored sample households/home geometry, hazard packs, commands and fixed event schedules. Unknown route/shelter/resource conditions must remain unknown.

## Actual source map

- `apps/ios/DryRun/Home/HouseholdSetupView.swift` selects `SampleHouseholds.all`: `hh-oak`, `hh-lake`, `hh-pine`; `Content/SampleHouseholds.swift` supplies distinct mobility, medical-device, transport, locale and supply constraints.
- `content/scenarios/{home-fire,tornado,flash-flood,freeze-power-loss,heat-grid-strain,water-outage}.json` each contain at least two gates. Flood has separate regional and household-leak gate pairs.
- `Simulation/ScenarioDefinition.swift` owns pack schema, known reviewed rule vocabulary and pack validation.
- `Simulation/HazardRules.swift` owns choice feasibility, services, fire/helper exclusions, shelter access and flood floor relationships.
- `Simulation/RehearsalEngine.swift` provides RunState, resource arithmetic, applicability and dependencies. `AuthoredSessionAdapter.swift` executes authored schedules/default choices.
- `Simulation/IncrementalSession.swift` executes only committed user/director commands, persists atomically, rejects stale/duplicate actions, previews by copy, and replays restored sessions. `SessionTransitionReducer.swift` unifies clock, schedule, depletion and scene mechanics.
- `Spatial/SampleHomes.swift` has five layouts: ranch, twoStory, apartment, apartmentComplex, manufactured. Existing tests include fire alternative/no-route/helper reach; interior movement preserves tornado objectives; water reserves and energy depletion; heat optional blackout and relocation gaps.

## Retain, extend, and remaining limitations

Retain distinct hazard rules, provider-neutral command contracts, authored compatibility and existing successful tests. Adaptive sessions intentionally reschedule events and permit intent choices before authored timestamps; practice evaluation separately rejects premature evidence. Imposing authored choice minutes would break established adaptive behavior, so no absolute-time gate added.

Implemented targeted fixes:

1. Incremental `choose` now validates the same applicability predicates as authored playback. A regional flood action cannot commit in household-leak practice or vice versa. Failed transaction remains unchanged.
2. Tornado `goToShelter` recommendation requires an actual graph route for every occupant under recorded mobility and active exclusions, in addition to a suitable room and dwelling. An isolated interior-room annotation no longer implies reachable shelter. Choosing intent still does not claim actual arrival.

New `ScenarioFamilyMatrixTests.swift` covers 3 families × 6 hazards × 5 homes (90 adaptive identity/commit/preview/duplicate/restore cells), with explicitly mapped per-person starts and at least two applicable gates per cell. It additionally tests flood variant atomic rejection, disconnected shelter recommendation, and paired essential/all-use water allocation with fixed initial quantity and elapsed time.

Important limitation: the 90-cell matrix proves committed decision transport and restored state, not two physical causal improvements per cell. Deeper hazard-specific acceptance still requires paired house/map/assessment work and reviewer-led native runs. The later IA-03 slice below replaces fire/tornado intent-only effects with supported modeled arrivals; general thermal `shelterInPlace` effects remain limited. Truthful simulation-versus-physical-evidence distinction must remain visible. No novel clinical, weather, safety or official route claims introduced.

## Evidence

Test command: `python3 scripts/review/firewall.py capture -- swift test --package-path packages/DryRunCore --filter ScenarioFamilyMatrixTests`.

Initial receipt: `run-8e3bc0c74c7b4958afd618451669464e`, failed, exit 1, elapsed 1220 ms. Logs protected; dedicated reviewer diagnosis requested from orchestrator. Escalated retry of the same command: `run-4f93e78e40a74f34b509b10600623687`, succeeded, exit 0, elapsed 30552 ms. No raw output inspected. The new deterministic suite passed on Mac; no live provider, simulator or physical-device claim.

Affected regression command: `python3 scripts/review/firewall.py capture -- swift test --package-path packages/DryRunCore --filter 'SimulationTests|SessionInteriorMovementTests|SessionPacingTests|PracticeNonDeviceTests'`, using the same compiler-cache escalation. Receipt `run-44b20a56ba0c4847840c9dd68f96b41f`: succeeded, exit 0, elapsed 3626 ms. Existing authored six-hazard behavior, interior route objective preservation, adaptive timing and non-device practice evidence regression suites passed. Exact test counts require reviewer-cleared diagnostics; receipt establishes process success only.

Shared causal contract: `docs/integration/scenario-house-contract.md`. Next owner: house specialist and orchestrator for paired spatial behavior; preparedness owner for evidence/score refresh; dedicated reviewer for test diagnostics/native evidence. No prompt/package change or live output experiment in this slice.

## IA-03 causal repair slice

Root approved a backward-compatible optional `occupants` extension in `Models/SpatialExercise.swift`. `Simulation/SpatialChoiceEffects.swift` now owns supported automatic choice effects through RunState's canonical dictionary. `takeExit` queries real routes with active exclusions and recorded mobility, then records each supported person's exterior exit portal. A separate outside gate accounts only already-exterior occupants. No geographic exit coordinate or real-world completion is inferred. `goToShelter` updates supported person-specific starts, route objectives and shelter arrival; inaccessible/missing shelters remain unresolved. Missing explicit helpers, unreachable helpers and unproven shared-helper simultaneous capacity cannot create dependent arrival. Existing `moveTo` rejects reentry from modeled exterior, synchronizes indoor/shelter positions, and leaves source snapshots immutable.

Occupancy is synchronized into existing snapshots, allowing the native cursor to show actual committed arrival without reading future result state. Root separately implements its native rendering. Later authored fire exclusions retain useful hypothetical route diagnostics but do not add actual egress/helper penalties to someone already outside. Old helper-reach regression now explicitly holds people indoors with a delayed unsafe choice and additionally proves timely exit avoids later helper penalties; its critical cause/exclusion assertions remain intact. `shelterInPlace` thermal effectiveness remains unresolved: choosing layers/stay-cool cannot manufacture adequate temperature or equipment capability.

New `SpatialChoiceCausalityTests` covers six authored/incremental cases: exterior arrival then distinct accounting, fixed-schedule alternative delay, earlier snapshot preservation, reachable versus disconnected tornado shelter, preview/commit/restore, no reentry, missing helpers, unknown windows/no exit, occupied fire origin, unreachable helper and authored/incremental shelter parity. These are simulated effects, never proof of physical safety or score completion.

Receipts retained:

- `run-74eb9049867c4e31a60f5b3c7c4a32a2`: selected existing regression failed; released `report-scenario-helper-causality-retest` diagnosed historical helper case setup drift (42 tests, one failure). Reconciled with explicit delayed branch and timely-exit comparison.
- `run-47e497b7c3ef44aca9c3cfea8590fe85`: first new causal test attempt failed while author correcting array append/predecision snapshot selection; raw logs not inspected.
- `run-8c5d2b4c4a4347d4a6a0d1217aa97b43`: first four causal tests passed.
- `run-f92cc3bf5ddb43b59f4b9246a7450059`: six causal plus selected regressions failed before historical helper expectation reconciliation; reviewer requested.
- `run-da6033eae678496e88e3d4981007735b`: six causal tests plus `SimulationTests|ScenarioFamilyMatrixTests|SessionInteriorMovementTests|SessionPacingTests|PracticeNonDeviceTests` passed, exit 0, 11430 ms.
- `run-c6b1159125484e3e99d216da320c3c36`: full Core regression failed, exit 1, 15986 ms; dedicated reviewer diagnosis pending. Latest tiny change gates outside-account recommendation on actual exterior presence. No more source changes pending diagnosis.

Historical contract reconciliation: released `report-core-full-legacy-digest-drift-1` diagnosed 494 tests/91 suites with only the pre-arrival whole-result digest test failing (12/24 hashes), and 493 other methods passing. The historical fixture remains unchanged. Versioned `AuthoredAdapterTests` preserves all 12 nonspatial full hashes and 10 spatial projected hashes. Its narrow projection removes the newly optional occupants field, restores prior scene stage IDs when the new scene advances on a choice, and restores the old unconditional outside-call recommendation for historical comparison. Two successful tornado default cases explicitly validate retained person/home identity and canonical shelter-route destinations instead of demanding obsolete start positions. No generic spatial skip or hash regeneration.

`run-98a288d9123e44f792a766b68be7bcd6`: versioned authored adapter, six causal tests and original SimulationTests passed, exit 0, 18792 ms. Additional helper correctness: helper reach alone is insufficient; the same recorded helper must continue to the same actual shelter/exit under its own mobility, excluding other exterior portals for the query. Modeled escort/helper exit matches the dependent; shared simultaneous capacity stays unproven. Independent planning overlays remain distinct from modeled occupancy.

Final current-source full Core receipt `run-785367c583ef443badcdb35ed6407164`: succeeded, exit 0, 19666 ms. Dedicated reviewer requested final count/contract classification. Source edits are frozen at this checkpoint for root's native build. No live/provider/native evidence is inferred from the Core pass; thermal `shelterInPlace`, additional flood timing consequences and complete all-six causal gates remain open.

Exact targeted invocation: `python3 scripts/review/firewall.py capture -- swift test --package-path packages/DryRunCore --filter 'SpatialChoiceCausalityTests|SimulationTests|ScenarioFamilyMatrixTests|SessionInteriorMovementTests|SessionPacingTests|PracticeNonDeviceTests'`. Full invocation omits `--filter`. Both use approved compiler-cache escalation. No generated runtime output or protected test logs inspected by the specialist. Native evidence, all-hazard physical consequences, score lifecycle and family-experience acceptance remain separate gates.

## Lead wave: six-hazard decision branches (branch `lead/scenario-learning`, base `cdb4098`)

Owner: scenario and learning lead. Scope: `packages/DryRunCore/Sources/DryRunCore/Simulation/**` and the new `Tests/DryRunCoreTests/HazardDecisionBranchTests.swift`. Requirements: HAZ-01..06, STRESS-01. No gateway, native, Ranking or Spatial edits. No mechanics version bump: the gateway's `hazardExperience` zod union is strict on fields and `feasibleCommands` must match `userCommand`, so every addition below is a new debrief fact kind (free `commandID` string, at most 100 facts, at most 20 subjects) or an existing command kind (`moveTo`). Replays of persisted v5 sessions stay valid because no previously valid command became invalid and no state or digest input changed. Authored playback has no `HazardProgress`, so the new records are adaptive-only and the versioned `AuthoredAdapterTests` hashes are unchanged.

### Feature-purpose record 1: thermal stay-in-place record (freeze, heat)

- Household and situation: a family that stays home during a freeze or heat outage, especially a member with recorded `coldSensitive` or `heatSensitive` needs (hh-oak's Grandpa, hh-lake's Bà).
- Improves: the authored `shelterInPlace` options (`keep-warm/layer-up`, `day-two/stay`, `hottest-hours/stay-cool`, `during-outage/stay`, `powered-evening/stay`) used to do nothing. In adaptive sessions they now record what the stay actually committed to: whether conditioning was available, whether recorded warmth or chosen shading was in place, which essential devices were unpowered, and which sensitive people had no protection at that moment.
- Known inputs and unknowns: services, `HazardProgress.protection`, shaded rooms, committed positions and device services. Thermal effectiveness is still unknown, so choosing to stay never adds warmth, cooling or device power.
- Why it belongs here: it uses the existing choice and debrief path with no new screen.
- Next step: one step. For heat the family shades a room (`reduceSolarGain`), and the host now offers `moveTo` for a heat-sensitive person into that shaded room through a supported path, using the same route authority and exclusions as `moveTo`. The stay record and the person's room range then differ.
- Evidence: debrief facts `thermalStayWithConditioning|WithRecordedProtection|WithoutRecordedProtection`, `thermalStaySensitivePersonExposed`, `thermalStayEssentialEquipmentUnpowered`, `sensitivePersonInShadedRoom|InUnshadedRoom|WithRecordedWarmth|WithoutRecordedWarmth`. Unprotected cases point to `prep.heatCold`, unpowered devices point to `prep.medicalBackup`.
- Simpler option considered: making `layer-up` apply recorded warmth automatically. It was rejected under v5 because a persisted `choose layer-up` followed by `warmLayers` would stop replaying. It needs a coordinated mechanics version bump with the gateway owner.

### Feature-purpose record 2: flood access-loss timing (refuge and supplies)

- Household and situation: a regional flood where lower spaces join the excluded set at the later `access-lost` stage.
- Improves: reaching the confirmed refuge, or carrying a supply, before that stage is now recorded as a timing consequence. Waiting is recorded too: the person's approach is lost, and stock left in an excluded space becomes inaccessible.
- Inputs: positions and refuge routes committed before the stage. These are recomputed from the existing `advanceFloodScene` and ledger, with no depth or arrival-time claim.
- Evidence: `atHigherRefugeBeforeAccessLoss`, `refugeApproachLostAtAccessLoss` (pointing to `prep.floodPlan`), `floodSupplyAccessLost`, `floodSupplyKeptAccessible`.

### Feature-purpose record 3: explicit no-supported-action versus objective reached

- Situation: a state where the home, needs or resources support no hazard action, for example no exterior exit, a manufactured home with no shelter and no contact, or no stored water while the tap is unavailable.
- Improves: the receipt now says so with `noSupportedHazardAction`, listing the open gap IDs as subjects. A completed objective (everyone out and accounted, everyone sheltered, or relocation) adds `objectiveReached` instead. No action is invented to fill the gap. The fact is state-derived, so a director `finish` does not change it.

### Feature-purpose record 4: debrief evidence from the action trace

- Improves: each committed user command adds an `action.<kind>` fact with its target and value as subjects and its own session event ID (the most recent 24 are kept). Director and debrief consumers can then explain a consequence from what was actually done, in order, instead of from a hazard-level summary.

### Causal acceptance tests (`HazardDecisionBranchTests`, 13 tests)

Each comparison holds the initial snapshot and the director schedule fixed: the authored event IDs fired are asserted equal across branches. Only household commits vary.

- Fire: exit now versus stay, then account versus not, across ranch/hh-oak, apartment/hh-lake, twoStory/hh-oak, manufactured/hh-pine and scannedRanch/hh-oak. Homes without a supported route assert that no escape is offered. Also covered: an occupied-origin variation and a home with no exterior exit.
- Tornado: shelter one person, versus also accompanying the child, versus none. The test checks the sheltered sets, `notYetSheltered` and the later accompaniment offer. hh-pine in a manufactured home gets no shelter arrival and an explicit no-action fact.
- Flood: leave early before the warning, versus carry the supply and reach the refuge before access loss, versus wait. The test checks the refuge approach, supply access and the departed branch's fallback `finish`.
- Freeze: allocate the station versus hold it, then warmth versus none before the stay choice. The test checks device service, backup Wh, temperature and the stay and sensitive-person records.
- Heat: shade a room plus move the heat-sensitive person, versus shade only, across apartment, ranch and twoStory. The test checks the occupant room, room range, exposure facts and that the move is retired after use.
- Water: essential versus all-use allocation, plus a stored-water drink. The test checks the later quantity and that tap use is unavailable. It also covers no stored water with no tap available.
- Trace: bounded to 24 entries, at most 100 facts in total, and the receipt is identical after restore.

### Evidence (deterministic-tested, Mac only)

- `swift test --filter HazardDecisionBranchTests`: 13/13 passed.
- Selected simulation regressions (18 suites, 120 tests) found two failures in `DepartureFallbackTests`: the finish-versus-before experience was no longer equal because the no-action annotation was skipped after `finish`. The fix makes the annotation independent of `finish`, and the 16 affected tests pass.
- Full Core suite with firewall capture: `run-65d93ab44760497082e4cdd5090875ac` failed before that fix, and `run-e313c88fa3d5405e96d7ddc1adab3b32` succeeded (exit 0) after it.
- `DirectorGatewayBridgeTests` regenerates `fixtures/ai/native-bridge/director-request-home-fire.json`. This is a host-built director request, not provider output. The lead did not open it; it adds 11 lines because of the new facts and is committed separately. The gateway `vitest run test/native-bridge.test.ts` validates it against the strict schema: `run-3f0b4c94b2234ec889c8767b5e8fbcef` succeeded.
- Full gateway `pnpm test` fails in this worktree both with the new fixture (`run-6fc400a99553423ea1480aa3a1665e82`) and with the original fixture restored (`run-0d6305c5279944d5b9414636cc433f3c`). The failure is present without this wave's fixture change and is unrelated to it. The cause has not been diagnosed and needs a reviewer.
- The unsigned generic-iOS `xcodebuild build` passed (`run-fe733a4870924d4d912bbd70fb7254e7`, exit 0), so Mac-build evidence exists. No simulator, phone or live provider run in this wave. The iOS app sees no public API change.

### Open items and next owners

- Practice checks: retiring completed checks already exists in `Ranking/HazardPracticeChecks`. Creating new checks from demonstrated gaps should come from `openGapIDs`, `noSupportedHazardAction`, `refugeApproachLostAtAccessLoss` and `thermalStay*` facts. Next owner: the preparedness specialist (Ranking scope).
- Gateway and director: the director prompt can cite `action.*` facts and the new outcome facts. The gateway owner should confirm that prompt and evaluation fixtures tolerate the extra facts and `moveTo` offers.
- Thermal effectiveness, and automatic warmth from `layer-up`, need a coordinated v6 mechanics contract. Freeze temperature is still whole-home, not room-scoped.
- Native: `moveTo` offers for heat should render as a "move <person> to <shaded room>" choice.

## Lead wave 2: native hazard choices, mechanics v6, practice-check repair (branch `lead2/scenario-native`, base `bd6974a`)

Owner: scenario and learning lead, with native rendering authority for `apps/ios/DryRun/Rehearse/**` this wave. This wave answers these audit findings:

- HAZ-01..06/STRESS-01 (critical: hazard decisions unreachable natively).
- Director quality G1 (freeze opening) and G2 (fire routes through the origin).
- The PracticeCheck possible regression.
- The house EgressPlanner acknowledgement.

### What changed

1. **Native hazard choices (critical finding).**
   - New Core `Simulation/HazardChoices.swift` turns `receipt.experience.feasibleCommands` into described choices: purpose, person, helper (current exercise assistance first, then the recorded helper), room (shelter, refuge, shaded room, the room an exit leaves from, where a supply is put), exit portal, destination, equipment/backup, contact, supply item, water source/activity/quantity, or gap. The primary objective comes first for each hazard, then household order.
   - `ExerciseActions.hazardOptions` renders them with `rehearsal.cmd.*` titles and accessibility identifiers `rehearsal.cmd.<kind>.<target>.<value>`. `AdaptiveRehearsalView` shows them in a "What your household can do now" card (`rehearsal.cmd.list`).
   - Every option is still previewed at the current revision with `session.preview` before it is shown, and committed through `model.submitAdaptive` → `SimulationSession.commit`.
   - The free person + room move picker is hidden whenever hazard choices exist, except flood (supply logistics). Generic `assignHelper` options are hidden too. Disconnecting a device (`allocatePower none`) and recognition-only `identifyGap` notes move to "Another action".
   - "What you did" describes each committed command from the command itself (`ExerciseActions.describe`), so it still names the exit after the exit is no longer offered.
   - The finished card lists the family's own actions in order (`rehearsal.cmd.trace`) and the family-readable debrief facts (`rehearsal.cmd.recorded`). After each turn, "What this changed" (`rehearsal.cmd.changed`) shows facts the receipt has newly recorded.
2. **Mechanics v6** (`dryrun.hazard-mechanics/6`). It is additive over v5, and every new effect is gated on `HazardExperience.level(version) >= 6`. v1–v5 sessions replay exactly as before.
   - **G2 fire origin:** when the director starts the alarm with an explicit origin room, that room is excluded from every route and escape from the alarm onward, and the scene marks it affected. A later `fire-origin` stage keeps that origin; before this fix it searched for a neighbouring room of the authored kind and found none. New fact: `fireOriginExcludedFromRoutes`. A person who starts in the origin keeps that start, and nobody re-enters.
   - **G1 freeze opening:** the local director asks the family once, after the opening key moment and before any household action, while home power still works. It asks only if the records support a preparation: `warmLayers`, a departure, `allocatePower` to a documented backup, or shading. The new user command `wait` ("Keep watching for now", `rehearsal.cmd.wait`) is the explicit alternative. It changes no state, is recorded in the trace, and is rejected on v5 and authored sessions.
   - **Outage readiness:** at the first committed home-power loss in freeze or heat, the session records what was in place: recorded warmth or shade, departure, and which essential powered devices had a documented backup. New facts:
     - `outageBeganWithRecordedProtection` and `outageBeganWithoutRecordedProtection` (subjects: exposed sensitive people);
     - `outageBeganAfterDeparture`;
     - `outageBeganWithBackupAssigned` and `outageBeganWithoutBackupAssigned` (→ `prep.medicalBackup`).

     Warmth chosen later does not rewrite the record. No warmth or cooling is ever manufactured.
   - Exact-version checks now use `level >= 4/5`, so v6 keeps every v5 behaviour. In `IncrementalSession` this covers the flood supply facts, the no-supported-action annotation and the departure/objective fallback. In `Ranking/HazardPracticeChecks` it covers composed checks and evaluator `hazard-checks/2`; that edit is mechanical, and preparedness should confirm it.
   - Gateway: `contracts.ts` adds a field-identical `mechanics/6` member to the `hazardExperience` union. `director-boundaries.ts` treats v6 departures like v4/v5. Without this, every v6 director request would fail the schema. `wait` is never in `feasibleCommands`, so the strict `userCommand` union is unchanged.
3. **House acknowledgement:** `RouteResult.algorithmVersion` goes from `egress-portal-graph/2` to `/3`. This versions the house operable=false doorway exclusion (`abaf408`), so cached `/2` routes recompute. Core tests regenerated the host-built native-bridge request and tool-result fixtures. I did not open them; only version strings change.
4. **PracticeCheck regression** (source diagnosis, not device-verified).
   - **Cause:** `PracticeCheckView.loadStep` withheld the whole step, including the authored decision card (`decision.option.*`), until every candidate action had been previewed. Each preview is a full session replay, and Oak/ranch fire had about 39, mostly door × person `closeDoor`. The UI test waits only 3 s for `decision.option.`.
   - **Fix:** the receipt and authored question now render immediately, and the authored step skips action previews. Door candidates are limited to doors next to each person's current room.
   - Hazard choices and their identifiers also render in practice. The person + room move picker stays, because it is the `adaptation` anchor. Feedback titles are described from the command.

### Locale keys

All keys are in `rehearsal.cmd.*` for en/es/vi (100 keys). es/vi are drafts by this lead and have not been reviewed by native speakers. Placeholders match across locales, so `selectableLocales` is unaffected. Power, contact and closeDoor reuse the existing `adaptive.*` keys.

- Chrome: `title`, `detail`, `notes`, `changed`, `recorded`, `trace`, `wait`, `unknownRoom`, `unknownDestination`, `liters`.
- Choices: `escape`, `accompanyEscape`, `accountOutside`, `reachShelter`, `accompanyShelter`, `reachHigherRefuge`, `leaveEarly`, `heatedAlternative`, `cooledAlternative`, `warmLayers`, `reduceSolarGain`, `moveToShade`, `takeSupply`, `transferSupply`, `identifyGap`, `water.{tap,stored}.{drink,prepareFood,hygiene,boiledDrink}`.
- Items: `item.{water,food,medication,firstAid,other}`.
- Gaps: `gap.{escapeRoute,escapeAssistance.person,shelterChoice,departureAccess,higherRefuge,higherRefuge.person,heatContinuity,coolingContinuity,roomCoolingCoverage,waterQualityOrService,storedWater}`.
- Done notes: `done.<kind>` for each choice kind, plus `done.wait`.
- Facts: `fact.<debrief kind>` for 34 kinds, including every new v5/v6 outcome fact.

### Destination labels (for house; recorded here rather than in the shared contract)

- Exits are labelled by the interior room their portal leaves from (`HazardChoices.exitRoom` + `HomeScenePresentation.roomLabel`).
- Shelter, refuge, shaded and supply rooms use `roomLabel`. Transport destinations use the household's own label.
- An unknown room renders "an unrecorded room", never a raw ID.
- If exits gain their own labels, `HazardChoices` can carry the portal label without a contract change.

### Evidence (Mac only; no phone, simulator or live provider)

- **`HazardMechanicsV6Tests`, 7/7 passed:**
  - v6 version and level;
  - explicit fire origin excluded across ranch/twoStory/apartment (Oak, Lake, Pine), with v5 replaying its old routes;
  - freeze opening asked once, never on v5 and never without a supported preparation;
  - prepared versus wait versus disconnect under one schedule: the outage record, device service and temperature differ, and the restored session matches;
  - `wait` accepted on v6 only;
  - descriptions for fire, heat move-to-shade and water choices;
  - tornado shelter/accompany choices retire after arrival.
- **`NativeHazardChoiceScriptTests`, 6/6 passed.** These mirror the phone scripts with the same family, home and local director:
  - heat shade → move;
  - fire escape → account, with the ordered trace;
  - tornado accompany + shelter;
  - water stored uses on a well;
  - boil-not-drink under the advisory (Lake);
  - flood: asserts that no sample home offers a refuge natively.
- **Full Core with firewall capture:**
  - `run-1542047599c64536bd14d698a67ce083` succeeded (exit 0) after the v6 change and before the new tests.
  - `run-d2f76b08352049b49c38858ecc9217a2` failed after the `algorithmVersion` bump. Only `AuthoredAdapterTests.preservesLegacyResultsOutsideVersionedSpatialArrivalFields` failed, with 10 issues: the 10 projected spatial historical hashes carry the `/2` label. The test now projects that route label back explicitly; the historical fixture is unchanged.
  - Final run `run-148b17a251ba4fba98ae1676c73b1cec` succeeded (exit 0) with all changes.
- **Gateway after fixture regeneration:** `vitest --exclude gateway.test.ts` passed (`run-17ceb6a166be481c8023bcd88c899dbb`) and typecheck passed (`run-8edf052508364b45bc7989522c61a713`).
- **Gateway:**
  - `pnpm typecheck` passed: `run-4a767a03c5714086a0d80de06d760721`.
  - `vitest run --exclude test/gateway.test.ts` passed: `run-a80956eafdce45d7876958031734751f`.
  - Native-bridge, thermal, flood, fire and director-schema tests passed: `run-86460214b8a949639e68715c7d0c8d0b`.
  - Full `pnpm test` fails only in `gateway.test.ts` (`run-b180a961f7714366b636a1d2f0c06dc7`). That failure is pre-existing: it also fails with this wave's gateway and fixture files reverted to `bd6974a` (`run-109fe87d2b314a92b314594afb09c13f`).
- **iOS:** `xcodegen generate` + unsigned generic-iOS `xcodebuild build-for-testing`: TEST BUILD SUCCEEDED, using its own derived data. The new `HazardChoiceUITests` compile but have not run.

### Open items and next owners

- **Flood refuge on device:** no sample family is offered `reachHigherRefuge` natively, which Core asserts. Adaptive sessions start without the setup's spatial options (`AppModel.openAdaptive`), and sample homes record no confirmed higher refuge or floor grade. Orchestrator: carry the authored setup's water-entry/refuge selection into `openAdaptive`. House: editor support for `higherRefugeConfirmed`/`exteriorGrade`. Core pairs remain in `HazardDecisionBranchTests` and `FloodRefugeActionTests`.
- **Freeze on device:** no sample family records a compatible backup, warmth or a destination, so the opening decision is honestly absent for unedited samples. The device check first toggles "works with" (`medical.worksWith`) for Oak's oxygen concentrator and battery station.
- **Codex-context:** gateway prompts still say "mechanics/5" and should say "/5 and later". Confirm that the director and evaluation fixtures accept v6, `wait` in `recentActions`/`lastAction`, and the new outcome facts.
- **Preparedness:** confirm the `HazardPracticeChecks` level gating. Consider an `adaptation` anchor for an `escape` through a supported alternative exit; the practice check now offers it, but it is unassessed.
- **UI:** visual/AX review of the choice card, the finished card and the es/vi wording.
- **Orchestrator:** the director job deadline and End-always-enabled (REL-01) are untouched here.

## Wave 3 (lead3/scenario, base 175d5c2, 2026-10-22)

Owner instruction: English only, blockers only. No AI output read; no device used.

- **P1 local director pin:** DEBUG launch argument `-localDirector` (`DemoLaunch.localDirector`) starts `AppModel.cloudDirectorEnabled` false. Used by `HazardChoiceUITests` (all) and the two DeviceAudit adaptive tests; the cloud-director tests (live Gemini, `BeaconUnplugged`, `DirectorDeadlineTests`) are unchanged. Release builds ignore the flag.
- **P2 water card:** no routing bug found. `RehearseTabView` pushes `NavigationLink(value: id)` per card and `RehearsalView` builds its setup from that same ID; nothing in `RootView` pushes home-fire. Most likely a tap during scroll momentum. SixHazard and DemoJourney helpers now wait for the frame to settle and assert the setup's own option identifiers (`rehearsal.setup.<scenario>.`), naming the wrong setup on failure.
- **P3 drift:** DeviceAudit water test uses `rehearsal.cmd.useWater.*` (Oak, ranch) instead of the removed "only for essentials" policy. DemoJourney `reveal` treats the rehearsal bottom bar (Replay/Next/Debrief) as covering, like the tab bar. Layout: the rehearsal scroll view uses `.safeAreaInset(edge: .bottom)`, which already insets scroll content, and fire has content below the decision card, so no layout change was made; whether the last option clears the bar is a device check.
- **P3 G1 freeze opening, mechanics v7:** `dryrun.hazard-mechanics/7` offers freeze `moveTo` into the room of the first at-home person with a recorded cold sensitivity, else a recorded mobility need, by a supported path (`HazardChoice.Purpose.gather`, titled with the existing `rehearsal.cmd.reachShelter` copy, so no new locale keys). The local director's opening decision counts it as a preparation. No warmth or temperature credit. v6 and earlier replay as before. Gateway: a `/7` literal in `contracts.ts` and `director-boundaries.ts`; host-built native-bridge fixtures regenerated (version and digests only).
- **P3 receipt titles:** `PoweredEquipment.receiptName` / `BackupPowerSource.receiptName` use the custom label, then `legacyOriginalLabel`, then the localized purpose or kind. `SimulationEvent.localizedTemplateValues` uses them and also resolves a device from its `svc.device.<id>` change. `SimulationEvent.receiptTitle` is now used for the debrief receipt labels in `AppModel` (these were raw `templateValues` and showed a blank sample device name).
- **House item 2:** acknowledged in `scenario-house-contract.md`.

Evidence (Mac only): `HazardMechanicsV7Tests` 6/6 together with V6 and NativeHazardChoiceScript (19/19, run directly). Full Core under firewall capture: `run-67ada46b760b4fe0a039fd6cd000dd7c` failed (`LocalDirectorTests` drivers did not handle the new open freeze moment; test helpers now answer it with `wait`), then `run-43d4635a9c944a8ab9eb0b253ce7279a` succeeded (exit 0; 671 Swift Testing tests in the failed run's count). Gateway `tsc --noEmit` exit 0; vitest full `run-a9a2a7d7b09a428c96c7790a2ee7787b` succeeded; native-bridge and director-private-context `run-2abd6e3ca7d0455ca1df7e04cc5f24ca` succeeded. `xcodegen generate` + unsigned generic-iOS `build-for-testing`: TEST BUILD SUCCEEDED. Nothing is device-verified.
