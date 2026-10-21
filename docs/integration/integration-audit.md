# Independent integration/scenario audit — interim gate

## IA-12–15 targeted source recheck — 2026-10-22

Independent synthetic audit, source only; no raw app outputs, logs, captures, stored preferences or generated assets inspected. Root's score-freshness changes are present; protected generic compilation is ongoing and is not a device result. No production edits or tests performed by this reviewer.

IA-12 is **implemented, acceptance unverified**: `PracticeStepIdentity` includes scope/attempt/session/revision/locale; `loadStep` clears old presentation and checks identity after both asynchronous queries; submissions validate the displayed source identity. IA-13 is **implemented, acceptance unverified**: persisted feedback acknowledgement separates recorded/revealed/acknowledged state, blocks next-phase questions until recovery, and supports retry after a failed reveal write. The current source addresses the earlier equal-revision collision and interruption loss without regrading answers. Required failure/relaunch tests and native interactions remain outstanding.

IA-15 is **implemented, acceptance unverified**: host score compilation now has a timestamp; `currentHostScorecard` requires matching source key and age under 60 seconds. Preparation, drill setup, debrief and director force a fresh computation before serializing that separate derived score record. This avoids persisting a derived score into its own input fingerprint. Request guards now include locale/private-state identity. `DirectorGatewayBridge` and `gateway.ts` now supply canonical private context and bounded `read_household_context` retrieval, so IA-10's earlier missing-source-contract statement is superseded; meaningful later-page retrieval/use remains a live-review gate. IA-08 real-household authorization remains open.

### IA-14 remains open through the focused review editor

Settings now gates reminders with `managesPersonalReminders`, but `FocusedHouseholdEditor.swift:263` still embeds `ReviewReminderSection()` unconditionally. The reusable section does not gate its schedule/cancel controls. Example review-card preparation can therefore modify the shared personal reminder even though example storage and delete cancellation are separated. Correct this at the reusable component boundary as well as entry points. Capture expected personal scope before the async authorization step and reject a changed scope before adding; cancellation must also recheck current permission. Test both Settings and focused review entry, including personal→example switch during permission await. Do not inspect owner notification data.

### IA-16 — withdrawn after authored localization verification

The initial source-key inference was incorrect: `adaptive.moved` is attempt wording in all three authored locales. English says the person tries to move, Spanish uses intenta, and Vietnamese uses thử. Thus blocked movement is not falsely presented as completed arrival by this label. No fix is required on this evidence. The earlier warning to root is retracted; this reviewer checked the actual locale values before finalizing the finding. No runtime output was inspected.

### IA-17 — medium, cancellation leaves preparation stuck working

REL-01, PREP-01. `AppModel.personalizePreparation` sets `(key,.working)` at line 1178 before awaiting forced score compilation. The cancellation guard at line 1180 returns without clearing that same-key state. Another explicit request for unchanged inputs is refused by the initial `.working` guard. Cancellation during this preparatory await can leave the existing Prepare action permanently loading until some unrelated context change.

Fix: use a request token and defer/finalization that restores retryable state only if that token/key still owns the operation. Do not clear a newer operation or another household's state. Test cancellation during suspended score compilation followed by a same-input retry; old completion must not overwrite the retry. This is a deterministic lifecycle fix, not a prompt-quality issue.

Remaining claims stay limited to source implementation. Exact current generic build/test receipts, failure injection and fresh plugged-iPhone review are required before closing these findings.

## Frozen native-source checkpoint — 2026-10-22

Synthetic independent source review after donor reconciliation. No production edits, test execution, raw-output reads or physical-device access. User unplugged the phone overnight; generic-iOS compilation receipt `run-bb0b9d48442c477d9cda574ce685e651` is compilation evidence only. Earlier IA-02 wiring description is superseded: AppModel authored choices now commit through `AuthoredRehearsalBridge` into the durable sidecar before publishing a cursor; adaptive commits likewise persist before publishing. IA-01 immutable editor scope is implemented (`ManualHomeEditorView` State plus `AppModel.updateHome` scope guard), pending current physical recheck. IA-06/07 source now uses owner window quotas and explicit `scopeProvider/configuredProviderConsent`; regression/live evidence is separate. Native client now validates response requestID/contextBinding and replay request fingerprints, addressing IA-11 source mismatch. IA-08 real-household authorization and IA-10 full director retrieval remain explicitly open.

### IA-12 — high, concrete source defect: practice phase reload uses revision alone

SCORE-01, UI-01, CTX-02. `PracticeCheckView.swift:45` keys `loadStep` only by the current session revision. `PracticeCheckSources.prepare` constructs initial response, communication and continuity sources with one setup commit each. Distinct phases therefore share revision 1. Communication→continuity can leave the old receipt/actions visible because the task ID does not change. `question` reads the new model step while the view retains old receipt/actions. `answer` submits those commands through `AppModel.submitPracticeAnswer`, which obtains the *current* step, rather than validating the displayed step identity. A stale communication action can become the first answer to continuity, or simply fail without explaining why. This undermines a consequential independent assessment.

Fix: key loading by scopeSessionID/attemptID/sessionID/revision/locale; clear old receipt/actions before awaiting; recheck that identity after each detached/action-query await. Submit with expected attempt/source session/competency/revision and reject mismatch. Test the entire four-phase sequence with equal revisions, rapid Next, family switching during query and relaunch. Assert displayed situation/action IDs match the exact phase graded, and untouched competency credit remains intact. Verify actual controls/feedback on the plugged phone when available.

### IA-13 — medium/high, concrete recovery gap: answer and feedback reveal are separate saves

SCORE-01, REL-01. `PracticeCheckView.swift:185-186` first persists an answer, then separately persists feedback revelation. The first transaction advances `practiceStep` immediately. If the second write fails, the guard exits without feedback; the current phase is already advanced and there is no UI retry for the accepted prior answer. A process interruption between these saves has the same effect. Atomic answer recording itself is good; silently losing the result is not a complete practice lifecycle.

Fix: retain durable pending-feedback identity and recover/retry its revelation before showing another question. Never resubmit/regrade the answer. Test failure specifically on the second write, interruption/relaunch after the first write, and retry; one immutable observation must exist and its feedback must remain reachable. Preserve before-feedback assessment semantics.

### IA-14 — high isolation defect: examples can replace the personal reminder

CTX-02, DEMO-01. `SettingsView.swift:38` shows `ReviewReminderSection` for every nonnil household. That section uses the shared scheduler; `ReviewReminders.swift:25,56,60-61` schedules/cancels a single `dryrun.review-plan` identifier. Example schedule/cancel therefore changes the personal reminder despite private/example vault separation and the example-delete cancellation guard. This is source-supported mutation behavior; no notifications were inspected.

Fix: disallow example reminder writes with a clear example-mode explanation, or explicitly namespace notifications/preferences by authorized household scope and keep the personal schedule intact. Tests: personal reminder → select example → schedule/cancel/reset → restore personal retains its original reminder; real personal cancel still works. Use injected notification clients and do not inspect owner notification contents.

### IA-15 — high context completeness gap: fresh displayed score is not supplied to AI

CTX-01, SCORE-01. `AppModel.refreshScorecard` at lines 112-135 derives a current score into observable `scorecard`; no AppModel path writes that result into `aiState.scorecards`. `AuthorizedAIContext.swift:121` exports only `state.scorecards`. A native user can see an updated score while preparation/drill/debrief retrieval sees an empty or historical score list. Shared full-context plumbing does not repair this missing producer.

Fix: include a typed host-computed current score/evidence snapshot and its exact source key in authorized context, or persist it atomically under an explicit freshness contract. Avoid fingerprint/regeneration loops caused by persisting derived scores into their own input digest. Tests: complete a practice answer, recompute score, serialize each feature request, and verify actual current components/coverage/supporting evidence are available through retrieval. Reviewer then verifies meaningful fact use; byte presence alone is insufficient.

### Remaining native evidence limits

Private/example save destinations now separate personal storage from ordinary in-memory examples; reload/reset guards and immutable editor scope are substantial source improvements. Preparation/drill/debrief now share full context and binding checks. Practice sources are frozen and first responses are persisted before UI feedback. These are implementation observations, not final behavioral passes. Current physical Save/relaunch, all 18 family/hazard cells with committed-state evidence, score refresh/retirement, notification isolation, accessibility and real RoomPlan remain for the phone queue. No current physical success is inferred from generic compilation or earlier builds.

## Donor reconciliation checkpoint — server contracts

Synthetic independent source audit refresh, 2026-10-21. This section supersedes stale architecture observations below where reconciled source differs. Production source clearance is recorded in `report-local-branch-production-source-clearance`; replay resources, fixtures, raw documentation and protected artifacts were excluded. No tests or device tools were run. AppModel/scenario reconciliation is still moving and awaits a separate frozen-source recheck. Auth transport, Gemini/Groq fallback, native gateway clients and public research now exist in source; the older statement that the server only has fixture auth is no longer current. Implementation is not live/native verification.

### IA-06 — high, proven source failure: lifetime quotas exhaust the shared server

Requirements REL-01, CODEX-02, GEO-01. `services/ai-orchestrator/src/http.ts:14` creates a process-lifetime Set; lines 36/42/48 reject every subsequent feature/intents/research call once its combined size reaches 100, across every owner. Entries never expire or leave after failure. `gateway.ts:28-32` similarly increments an owner count to 12 without a reset/decrement/window. `resource-discovery.ts:21-28` uses a singleton lifetime call counter with maximum 12 supplied by `server.ts`; line 46 requires two remaining calls. A family's repeated practice or a few research comparisons exhaust useful functionality until server restart, and one installation can consume the HTTP/research budget for all others.

Correction: separate bounded replay-dedup retention from per-owner/per-operation call and spend budgets. Use TTL/LRU request receipts, a defined renewable rate-limit window and explicit Retry-After; keep fresh per-operation tool limits. Release concurrency reservations in finally; preserve replay protection for the documented retention interval. Tests with injected clocks: >100 completed unrelated operations remain available after the window; one owner's exhaustion leaves another functional; duplicate within TTL is rejected; failure/cancel does not permanently consume process capacity. Preserve all actual model failures for review rather than retrying until a win.

### IA-07 — high, proven source contract mismatch: Codex bypasses provider consent

Requirements CTX-01/02, CODEX-01, REL-01. `http.ts:47` and `contracts.ts:88` permit only Gemini/Groq consent; omitted consent defaults to Gemini. `server.ts` selects a Codex singleton by environment. `features.ts:101` and `gateway.ts:33` use `provider.scope?.(...) ?? provider`; Codex has no scope method, so Gemini-only requests can send private records to Codex. Image requests likewise rely on downstream transport checks rather than a common capability policy. This does not demonstrate an observed disclosure; it establishes a code path contrary to the typed consent contract.

Correction: define explicit provider identity/capabilities and enforce consent before any provider call, including unscoped implementations and public research. Add Codex to the authorized configuration/native consent contract deliberately; do not interpret Gemini permission as Codex permission. Test no provider call on unsupported consent/image capability, supported Codex call only under explicit allowed configuration, and fallback never expands permitted providers. Keep server credentials out of native configuration.

### IA-08 — high acceptance gap: restored authentication remains synthetic-only

Requirements CTX-01/02, DEMO-01, CODEX-01. `app-attest.ts` signs and authorizes only `scope:'synthetic'`; native `AppAttestSession.swift:57-61` requests that scope. `PreparationFeatureBridge.swift:38` rejects nonfictional households, and server feature/operation/research schemas require `synthetic:true`. App Attest supplies a real installation identity mechanism, but it does not establish an authorized real-household data path. Keys/challenges/counters are in memory and the module itself identifies durable storage and endpoint rate limits as deployment work. These are explicit prototype boundaries, not evidence of a cross-family exploit.

Correction: retain safe synthetic development while specifying a server-authorized real-household/session binding and explicit cloud consent. Never simply remove the fictional guard. Bind retrievable snapshots and operations to that authorized scope, persist attestation state for a deployment profile and define retention/revocation. Test real-mode isolated synthetic household through normal persistence/auth, owner A/B separation, key/restart recovery, reset and cancellation. No owner household is needed for these tests.

### IA-09 — medium/high, source-supported context integrity risk: reader validates only revision

Requirements CTX-01/02. `private-context.ts:15-18` requires a nonempty owner and matching household revision, but does not compare the embedded household/origin/session/home/inventory identity with an independently accepted operation binding. `features.ts:91` supplies only owner and anonymous household revision. Reads are closure-scoped and accept no tenant selector, which is good, but mixed snapshots with coincident revisions are not rejected. All data is client-supplied today, so this is not evidence that the server can retrieve someone else's records; it is an integrity gap that can make one family's decision use mismatched context.

Correction: validate the full expected scope/revision vector against a host-authorized envelope before creating the reader. Include a consistent identity in completion acceptance. Tests: same revision/different household, origin, session, home and inventory fail; immutable snapshot pagination succeeds; a changed section filter cannot reuse a cursor ambiguously. Oversized records currently return explicit unavailable handles rather than silently fabricating absence; retain this behavior and require reviewer diagnosis of decision-changing unavailable facts.

### IA-10 — high acceptance gap: rehearsal context has no full canonical retrieval contract

Requirements CTX-01, CODEX-02, HAZ-01..06. Full private records are integrated into feature preparation via `PreparationFeatureBridge.Context.privateContext`, but no `privateContext`/`read_household_context` is defined in `DirectorGatewayBridge`, `contracts.ts` or `gateway.ts` at this checkpoint. Director tools inspect scene/routes/dependencies/previews and remain useful; they do not establish complete medication/storage/equipment/history/score retrieval. Do not cite preparation retrieval as proof for every operation.

Correction: project an authorized full snapshot/manifest into the director path with the same scope/revision guarantees, while keeping the initial scene compact. Test a decision-changing fact available only on a later retrieval page and verify meaningful use with dedicated output reviewers, then repeat after continuation/resume. Freeze exact expected paired decisions before generating results.

### IA-11 — medium, source-supported stale replay risk: fixture identity substitutes for snapshot

Requirements CTX-02, PROMPT-01, DEMO-01. `DirectorGatewayClient.swift:168-170` falls back to a recorded preparation selected by household ID, then returns the current request's household revision. `recordedPreparation` at lines 263-269 checks an `hh-` prefix and decoded status, not fixture revision/context hash/locale/home/session. Replay is labeled, and bridge acceptance rejects invalid task references, which helps. Yet a valid reference with outdated reasoning may survive material fixture edits or a paired evaluation. No replay asset was opened by this audit.

Correction: require an explicit immutable recorded-fixture manifest matching expected context/prompt/provider/locale/home revisions and preserve original provenance; never restamp a recording as freshly evaluated. For changed/held-out facts, return truthful local/unavailable behavior rather than an old personalized conclusion. Tests must verify changed budget/equipment/home/session cannot produce a recorded-completed result as current evaluation. Keep live/recorded/local results distinct in native UI and the ledger.

### Prior IA-01 status and physical provenance

Root reports immutable editor `savedScopeSessionID` and native stale-family/reset tests implemented; source recheck belongs with the pending frozen AppModel review. Status: implemented-unverified, not closed by earlier units. Released `report-integrated-native-unit-core-pass` is reported to cover 48 physical methods with zero failures and 50 selected Core tests before that scope patch; it must not be used to certify later donor reconciliation. The earlier feedback-only native matrix remains reachability evidence unless strengthened committed-state/persistence assertions and reviewer findings are supplied. All new claims require exact integrated build and plugged iPhone 16 Pro evidence.

Gate remains open. Highest priority is consent enforcement and renewable isolation-aware budgets, followed by authorized real/context scope and a frozen end-to-end native action audit. Public research/source support and actual model usefulness require released semantic reviews; source capability declarations alone cannot pass them.

Synthetic agent source audit by integration_audit. Base HEAD `26332ded170f2fea414d581fb50d5de6f4093ab9`, shared uncommitted integration work inspected on 2026-10-21. This is an interim gate, not completion or real-family validation. Production code was not edited. No device was accessed and no protected responses, screenshots, logs, accessibility trees or persisted content were inspected. Evidence consists of authored source/contracts and released reports. The checkout is changing concurrently; fixes below require reinspection against a frozen integrated build.

## Gate: consequential integration work remains

### IA-01 — high: stale home drafts lack scope identity

Requirements CTX-02, HOME-02, DEMO-01. Source-supported risk, not observed device failure. `HomeTabView` constructs `ManualHomeEditorView` with `savedBaseRevision`; its Save passes only the edited home and optional revision to `AppModel.updateHome(_:baseRevision:)`. That guard compares only the currently active home's optional revision. Equal revisions do not identify a household or reset session. The lower overload deliberately rewrites the submitted home ID to the current active home. A still-open old sheet can therefore submit geometry into a different family with the same revision, including an identical example reset. A shared home ID would not repair this.

Expected: the exact household/origin/session and saved-home revision that opened the editor remain current. Correction: capture immutable `scopeSessionID` in editor State at initialization, pass it with every Save, and reject mismatch before persistence. Include expected home identity where it can differ within one scope. Preserve the existing draft on rejection. Audit direct save callers so they cannot bypass the guard. `privateWriteInFlight` already serializes private saves; verify load/reset cannot interleave publication across the persistence await.

Retest with native in-memory stores: A opens rev N → switch B rev N → old Save rejected; same family reset at rev N → old Save rejected; unsaved nil-base draft → new scan rejected; current same-scope Save succeeds; failed Save keeps draft and canonical state unchanged. Run UI persistence/relaunch checks on the plugged iPhone 16 Pro through the designated output reviewer. Root was notified before implementation.

### IA-02 — blocking: native rehearsal and tested incremental session are different paths

Requirements HAZ-01..06, SCORE-01, CTX-01, CODEX-02, MAC-01. Proven source wiring gap. `RehearsalView` calls `AppModel.choose`; that method changes `RehearsalInput.choices` and reruns `RehearsalEngine` into `RehearsalCursor`. It does not commit `SimulationSession`, persist its trace, capture practice evidence or refresh a scorecard. The new 90-cell `ScenarioFamilyMatrixTests` exercises incremental `SimulationSession`, not this native consumer. Its success cannot certify native causal action/evidence integration. The native view is deterministic; no actual Codex invocation is demonstrated by that journey.

Expected: the existing scene-first native experience uses the same authoritative action/evidence lifecycle being claimed and tested. Correction: connect the existing incremental session and practice contracts to this native flow, retaining the useful cursor presentation where appropriate; do not create another movement/evidence store. A useful first vertical slice should persist one supported action, present its committed effect, reopen it, retire its practice instance and refresh every score surface. Then cover all six hazards. Test failure/cancel/stale callbacks without publishing invalid state. Keep legacy authored playback compatibility explicitly separate.

### IA-03 — high: major spatial choice effects remain intent only

Requirements HAZ-01..03, HOME-01, GEO-02. Proven source limitation, not a rendering claim. In `HazardRules.choose`, `goToShelter` only inserts a flag when infeasible; successful selection changes neither occupant location nor shelter status. `takeExit` and `shelterInPlace` have no dedicated effect and reach the default branch. `SimulationSession.moveTo` does support actual interior relocation, but it is not automatically a consequence of those choices and cannot represent exterior arrival. The specialist causal contract correctly acknowledges these gaps.

Expected: two consequential decisions per hazard change committed state, feasible continuation or defined eligible evidence. Correction: represent person/destination and authoritative arrival/accounting separately from intention. Use existing validated route queries and active exclusions. An unavailable route must stay unavailable; do not give arrival credit for selecting an intention. Retain `PracticeEvaluator`'s explicit initial-response intent anchor without relabeling it physical egress. Add fixed-initial-state/fixed-event-schedule alternative-choice tests and inspect changed native geometry/state through reviewers. Cover blocked connector, isolated shelter, unknown window, no supported exit and distinct flood/leak variants.

### IA-04 — blocking acceptance gap: live integration is not yet established

Requirements CODEX-01/02, CTX-01, GEO-01, PROMPT-01. Released `report-codex-live-probe-1` records an actual LB 503 before tool requests or text deltas. No successful inference, search/open, schema, continuation or vision is established. `server.ts` exposes a loopback fixture-authorized development server and explicitly refuses production. `codex-config.ts` requires attested capabilities, appropriately preventing accidental enablement. New private-context source is under active implementation and is not evidence of bytes reaching a native-triggered request or meaningful fact use.

Correction: finish the existing typed gateway consumer and authorized snapshot/retrieval bridge, then obtain supported-alias compatibility through the exact synthetic probe with successful terminal status. Require real tool/result matching and schema validation before attestation. Preserve Gemini/Groq/offline capability paths. Live research must use real search/open or an explicitly labeled existing external research bridge; bundled records are not automatic discovery. Conduct baseline/competing hypotheses/repeats/fresh held-out and native-fit reviews, with every failure retained. Do not weaken capability gates to work around unavailable upstream capacity.

### IA-05 — high: native matrix asserts feedback existence, not committed consequence

Requirements DEMO-01, HAZ-01..06, AUDIT-01, MAC-01. Proven test coverage limit. `FamilyHazardMatrixUITests` enumerates the three actual families and six actual hazards, selects the first button and waits for `rehearsal.choiceFeedback`. It captures before/after, but never asserts correct identity/context, a persisted meaningful action, corresponding deterministic visual state, score/retirement, no-supported-action handling or reopening. Feedback visibility is compatible with IA-02/03 remaining unresolved.

Correction: extend reviewer-driven cases with deterministic safe receipts for the selected scope, action/commit ID, relevant before/after state, displayed scene revision and accepted persistence result. Avoid exposing generated text in receipts. Cover every cell plus deeper alternatives, restore/reset/in-flight family isolation and real-mode synthetic boundary. Freeze exact build/runtime/provider/fixtures. This smoke suite can remain a useful reachability check if named and reported accurately.

## Native provenance and remaining evidence

Released `report-native-unit-and-core-blockers` records 45/46 methods passing on the plugged iPhone 16 Pro, compiled before later integration changes. The failed method observed display-label-only home edits erasing exit/drill timestamps. Root has a source normalization fix in progress; fresh physical retest is required. The same report discloses that the first unit host started without explicit in-memory launch arguments; no owner content was inspected, but that run must not be described as fully isolated.

Released `report-native-baseline-captures-1` covers five ordinary-size English dark baseline surfaces, primarily Oak and fire variants. It verifies the actual capture/clearance path and identifies task alignment/palette/density defects. It contains no committed-decision evidence and is not a post-fix audit. There is no basis to claim all-family native smoke, all-six visuals, accessibility size/VoiceOver, durable editing/relaunch, current score refresh or physical RoomPlan scan. Imported RoomPlan fixture tests do not establish a real scan.

Released `report-core-preservation-regression-1` records 47 tests and one historical expectation conflict across four assertions. The proposed per-competency preservation contract is consistent with requirements; a passing rerun is still necessary. Preserve unrelated independent competency evidence and do not award stock/physical preparation from practice answers.

Maps scope-key cleanup and ordinary-directions limitations are useful source improvements. Their report explicitly leaves automatic context-specific live discovery, official hurricane instructions, indoor-exit handoff, simulated flood alternate consequences and tornado shelter linkage open. Current source now includes `scopeSessionID` in map scope; retest reset-with-identical-address as well as A→B during search/route/editor activity. Address/coordinates alone must never georegister a door.

## Recheck order

1. Close IA-01 and obtain protected deterministic regression receipt plus reviewer diagnostics.
2. Integrate the smallest native action/persistence/evidence/score slice to close IA-02, then causal spatial gaps in IA-03.
3. Rebuild the integrated physical destination and rerun affected native units with explicit isolated host launch arguments.
4. Execute strengthened 18-cell native matrix and deep branches under serial reviewer reservation; obtain measured post-fix UI captures and persistence traces.
5. Close live compatibility/context/research and prompt experiment gates with independent reviewer reports; complete family-experience audit separately.

No tests were run by this audit and no success is inferred from source inspection, build success or another agent's receipt alone. This report requires a final independent recheck after material fixes and a frozen integrated evidence manifest.
