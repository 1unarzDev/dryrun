# Exercise inventory, source and command contract

Reference sections 7 and 10 require confirmed intake, conservation and access; hypothetical use must not alter real facts. `SessionInventorySeed(ledger:asOf:)` is an optional immutable source for `SimulationSession`. Missing seeds preserve legacy sessions and their existing replay digests. The native start/resume owner must attach the confirmed current ledger and an explicit reference date when creating a new exercise. Never substitute a later ledger during resume; source edits require a new/forked exercise.

`dryrun-host`'s `confirmInventory` now creates a seeded session after atomic household projection. `SessionReceipt.inventory` contains derived `ExerciseInventory` with sourceRevision and per-item id, physicalID, category, unit, optional remaining, consumed, optional locationID/carrierPersonID/accessibility. Its absence identifies the legacy aggregate adapter. This source and derived state participate in the session digest. The source remains unchanged in every commit and is persisted with the session, never sent wholesale to the gateway.

Whole-container user commands:

```json
{"id":"submitted-transfer","actor":"user","baseRevision":0,"commands":[
  {"kind":"takeSupply","target":"water-container-id","value":"person-id"},
  {"kind":"moveTo","target":"person-id","value":"sp-living"},
  {"kind":"transferSupply","target":"water-container-id","value":"sp-living"}
]}
```

Taking requires known access, a known storage room, and the submitting person currently in that room. Moving uses existing hazard-aware host routing. Transfer drops the carried item at that person's actual current room; it cannot teleport supplies, split quantities, replenish them or move a person without a move command. A director cannot commit either supply action. An infeasible batch fails atomically; retain/report the submitted intent rather than replacing it with another action.

Water consumption uses existing RunState demand and mandatory depletion boundaries. The exercise ledger settles that exact draw across accessible containers in stable item-ID order, converts gallons/liters, and tracks remaining+consumed in original units. This is a deterministic accounting convention, not a recommended ordering of household use. Blocked stock remains physically present but contributes zero accessible water. Access uses the current confirmed graph and committed hazard exclusions. A carried item follows its person's actual location. An unreachable storage room removes access; missing geometry for a specified location remains unknown. A container with no location retains its explicitly confirmed access, so a hazard cannot be assigned to it without a location fact.

Expiry is another mandatory boundary. At minute resolution, a fractional-minute expiry is conservatively rounded down, expiring at most one minute early. Unknown quantities/access remain unknown; the engine does not invent a draw or certain endurance. Non-water quantities/locations are retained and transferable, but their consumption has no universal model. No automatic pharmacy dosage, infant/pet allowance, food/fuel arithmetic or inventory replenishment is claimed. Household source confirmations and accepted requirement gaps remain separate.

`PlanStressTester` and read-only `runCounterfactual` accept the same seed and bind a sourceInventoryDigest. Stress execution can therefore expose loss of accessible storage, without changing real stock. These counterfactuals start from initial facts; they do not apply current exercise transfers. Inventory-changing interventions need explicit ledger semantics before they can add stock to a seeded controlled comparison.

Run `pnpm --dir services/ai-orchestrator exec tsx scripts/inventory-session-eval.ts` after building Core. The synthetic trace includes confirmed source, submitted transfer, blocked-storage and protected-stock branches, identical real facts, exact replay, and a source-bound stress result. Native controls should combine select-container/person and destination actions within the existing rehearsal scene; no new inventory-agent tab is needed. Device UI/VoiceOver usability remains unverified.
