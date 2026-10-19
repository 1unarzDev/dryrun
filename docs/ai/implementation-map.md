# Verified implementation map
Baseline main / 436b243276e0f333131a1813b580382971949748. Root reference supplied as .md, 769 lines; read before design. No applicable AGENTS.md. Untracked owner audit/handoff files preserved.

RehearseViews → AppModel.startRehearsal → RehearsalEngine.run → RunState.execute / BackupAllocator / HazardRules / EgressPlanner → RehearsalCursor → scenes. choose reruns authored schedule. New SimulationSession reuses RunState/rules; native migration belongs to Mac.

Household forms → AppModel.updateHousehold → HouseholdEditing cleanup → PrivateSnapshot → save via PrivateDataStore/VaultPrivateDataStore → publish → configureRegionalResources/invalidateDerived. Proposal acceptance must keep this save-first boundary.

Owners: Core arithmetic/routes/score; AppModel/Vault persisted facts; gateway transient bounded jobs; public-api public evidence only. Immutable source snapshot per exercise: source edit requires fork or explicit continuation against original revision.

Native checkout includes card/PDF selection, scene-first cursor, focused editors, manual/RoomPlan, on-device intake/briefing and maps. Newer owner-reported work is not reconstructed. Native files untouched.

Baseline: Swift 6.2 Docker, 333 Core tests pass; Node 26.11.1/pnpm12.14.0 public-api 68 tests plus tsc pass. No system Swift; Docker works. Secret presence checked without value. Private gateway isolated Node runtime, no public Worker changes.
