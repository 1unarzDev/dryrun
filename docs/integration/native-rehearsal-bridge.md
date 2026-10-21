# Native canonical rehearsal bridge (IA-02)

Owner: scenario_learning; orchestrator owns UI, shared persistence and signed-device integration. Requirements IA-02, HAZ-01..06, DEMO-01, CTX-02, REL-01. This engineering note contains authored source findings and safe command receipts, no app-generated responses.

Reconciliation update: the scored-phase limitation below describes the earlier root checkout slice only. Cleared completed production work from `5f95135` and selected complementary modules from `a9efc8f` has now been reconciled into this working tree: adaptive canonical sessions, linked four-phase practice, hazard-specific anchors, inventory, scorecard, debrief and preparation feature bridges. The authored bridge remains a separate explicit legacy-mode educational path; it does not generate practice credit. Current compile/test and physical verification status must be taken from subsequent released receipts, not inferred from source restoration.

## Family purpose and contract

A family answering a practice decision should see the consequence of the actual accepted action, keep that answer when reopening the app, and retain its previous valid state if Save fails. The existing rehearsal scene and key moments remain the flow; no extra setup, destination or clock was added.

`AuthoredRehearsalBridge` extends the existing canonical `SimulationSession` and shared reducer rather than a second engine. It initializes without any answered choices, schedules only applicable authored events up to a boundary, advances real resource/depletion boundaries, checks the earliest unanswered applicable decision, and commits one explicit user `choose`. There are no model-generated or default user commits. Authored display input is derived only from accepted user commits.

The displayed authored result remains an educational projection for future unvisited moments. At each accepted choice's exact event-reveal boundary the bridge inserts the authoritative session receipt snapshot, including resources, services, spatial exclusions and per-person occupancy. It cannot show a future arrival before that choice is visible. The native cursor reveals the just-accepted choice immediately and stops there; resume returns to the last accepted choice and its feedback.

## Native transaction and isolation

`AppModel.startRehearsal` and `choose` prepare a full candidate `IntegratedAIState.sessions` sidecar. They compare the household/home/content revision key, immutable scope-session identity, active session ID and original opaque sidecar bytes before Save. `save(snapshot:)` atomically persists the whole private snapshot before the new cursor, receipt, ID or answer becomes observable. A write-in-flight guard prevents repeated taps from invalidating the already-saving action. Failed saves keep the old cursor/receipt/data unchanged, enabling retry. Concurrent sidecar changes are rejected rather than overwritten.

Native session IDs use `native-rehearsal-v1/` within the existing private sidecar. Resume requires exact initial household, home, scenario/content versions and variants. Reset clears the sidecar through the existing reset transaction. Root wires restore after private-load invalidation, clears receipts on derived-state invalidation, and passes `restart: true` from the explicit Restart button. Ordinary navigation resumes; explicit Restart creates a fresh canonical session. Other integrated sessions and score evidence are preserved.

Facts in `SimulationSession.initial` remain immutable. Simulated movement and arrival are reconstructed by the shared domain reducer. Neither arbitrary practice answers nor simulated arrival establish real purchased supplies, physical route checks or numerical preparedness credit.

## Files

- Core `Session/AuthoredRehearsalBridge.swift`: canonical initialization, applicability/order checks, schedule/depletion advance, user choice and receipt projection.
- Core `Tests/.../AuthoredRehearsalBridgeTests.swift`: three tests, including all three actual families across all six hazards and every applicable gate.
- Native `App/AppModel.swift`: start, choice, sidecar-save guard and exact-input restore helpers; root owns load/invalidation integration.
- Native `DryRunTests/AppPersistenceTests.swift`: five added methods for six-hazard save/reopen, failed start, failed choice/retry, scope/reset/material revision isolation, held-write duplicate-choice/reset serialization.
- Root `Rehearse/RehearseViews.swift`: existing Restart button explicitly restarts; native occupancy rendering remains root-owned.

## Executed evidence

- `run-d93787c5466348159dfc44a7aa97e459`: `python3 scripts/review/firewall.py capture -- swift test --package-path packages/DryRunCore --filter AuthoredRehearsalBridgeTests`, passed, exit 0, 25787 ms. All explicit choices over the 18 family/hazard combinations, restore equality, authoritative receipt resources/services/spatial state, no implicit initial/default answers, duplicate/order/variant atomic rejection and no premature fire arrival.
- `run-6b6502f0000d4eb3b82807897e5763fb`: full Core command without filter, failed, exit 1, 32654 ms; dedicated output reviewer asked for exact diagnostics. Root had independently reported a ScanImport fixture-dimension regression before this run; do not assume it is the sole failure until the released report confirms.
- `run-0619de2cee45441ab68965c9631b16d9`: protected unsigned generic-iOS `xcodebuild build-for-testing`, passed, exit 0, 51261 ms.
- `run-833abff7bd33477e8af8d895b5c6c524`: repeat protected unsigned generic-iOS test compilation after transaction guards, passed, exit 0, 21271 ms. Native tests were compiled, not executed on a simulator or phone by this specialist.
- `run-5a245c3143074e728eba55016b9b3201`: final frozen-source generic-iOS build-for-testing, passed, exit 0, 12294 ms; includes the five added native persistence test methods. This removes ambiguity from earlier builds that overlapped test authoring. No native test execution claimed.

Exact native command: `python3 scripts/review/firewall.py --timeout 900 capture -- xcodebuild build-for-testing -project apps/ios/DryRun.xcodeproj -scheme DryRun -destination generic/platform=iOS -derivedDataPath /private/tmp/dryrun-protected/native-bridge-build CODE_SIGNING_ALLOWED=NO`. Compiler-cache/native-build escalation was approved. No device was accessed. No raw logs were inspected.

## Outstanding gates and next owner

Root/reviewer must rebuild the current signed integration, execute the five native persistence tests, inspect actual six-hazard scene/feedback and relaunch through the output firewall, and retest family/reset/in-flight behavior. A successful generic build is not device acceptance.

This authored slice saves canonical choices and consequences; it does not implement a new scored practice attempt. The restored adaptive `beginPractice`/phase submission path supplies pre-feedback competency anchors and multiple linked sessions, with separate inventory and score surfaces. Arbitrary authored rehearsal choices are not routed into it for synthetic points. Finish/timeline-only navigation remains an educational projection and is not persisted as scored completion. Native execution of the restored practice flow remains a verification gate until supported by an explicit released native receipt.

Additional hazard gaps from the earlier specialist report remain: supported thermal stay-in-place effects, stronger flood early-window consequences and complete all-six native causal/debrief coverage. No live Codex or provider-quality claim is made by this local deterministic bridge.
