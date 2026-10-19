# Verified implementation map
Baseline main / 436b243276e0f333131a1813b580382971949748. Root reference supplied as .md, 769 lines; read before design. No applicable AGENTS.md. Untracked owner audit/handoff files preserved.

RehearseViews → AppModel.startRehearsal → RehearsalEngine.run → RunState.execute / BackupAllocator / HazardRules / EgressPlanner → RehearsalCursor → scenes. choose reruns authored schedule. New SimulationSession reuses RunState/rules; native migration belongs to Mac.

Household forms → AppModel.updateHousehold → HouseholdEditing cleanup → PrivateSnapshot → save via PrivateDataStore/VaultPrivateDataStore → publish → configureRegionalResources/invalidateDerived. Proposal acceptance must keep this save-first boundary.

Owners: Core arithmetic/routes/score; AppModel/Vault persisted facts; gateway transient bounded jobs; public-api public evidence only. Immutable source snapshot per exercise: source edit requires fork or explicit continuation against original revision.

Native checkout includes card/PDF selection, scene-first cursor, focused editors, manual/RoomPlan, on-device intake/briefing and maps. Newer owner-reported work is not reconstructed. Native files untouched.

Baseline: Swift 6.2 Docker, 333 Core tests pass; Node 26.11.1/pnpm12.14.0 public-api 68 tests plus tsc pass. No system Swift; Docker works. Secret presence checked without value. Private gateway isolated Node runtime, no public Worker changes.

## Housing/site expansion verified in this checkout

Household edit ownership remains AppModel.updateHousehold → HouseholdEditing → atomic private snapshot save → publish/invalidate. SiteHazardEditing.stage participates without owning a second revision; standalone replace owns its own revision. Type changes propagate into HomeModel; moveHome clears site evidence. Native adapters/UI/production auth are still integration work. Earlier “native files untouched” describes the initial baseline only; current narrow edits are listed in the phone handoffs and require Xcode verification.

AnonymousHousing + minimized SiteHazardContext accompany household-bound HomeSceneContext. HousingPlanning routes/needs are baseline geometry; SessionTools/queryRoutes/evaluateCandidateAction own incident-specific results. HomeSafetyMarkers owns validated candidate placement; existing editor/Vault owns persistence. HomeModelExport shares floor transforms with portable SVG/OBJ and the native dollhouse. SampleHomes adds original apartment-complex/manufactured models, preserving unit-only apartment, ranch and two-story models. HouseholdAssessment/6 rejects legacy manufactured-interior shelter credit; model and hypothetical evidence never establish real facts.

Gateway preparation/7 and resources/5 retain bounded Gemini selection and host-owned task identities, critical priorities, inventory proposals and compiled shelter/CO/exit-review explanations. output-quality/1 audits actual text as review flags, never a safety score or truncation rule. New tests and actual retained synthetic live traces are detailed in evaluation-report.md and housing-location-support.md.
