# Host-owned practice capture

Reference §12 requires eligible evidence before feedback. `IntegratedAIState` now owns the complete local capture transaction. Do not pass caller-created `PracticeAnswer` values into production scoring. The old `recordPracticeAnswer` entry point is source-compatible but rejects all writes; `beforeFeedback=true` cannot prove chronology. The low-level `ScoreCompiler.compile` still accepts trusted assessment inputs for frozen arithmetic fixtures. Native uses `IntegratedAIState.compileScorecard`, which reconstructs eligible practice answers from the bound committed traces.

1. Persist `beginPractice(id:variantID:sessionID:library:persist:)` before presenting the optional check in Rehearse. It freezes variant, session source (initial household/home, inventory seed, policy), revision and event sequence. An interrupted latest attempt resumes with its original identity/variant. Each retest needs a new session; an old coached trace cannot be relabeled as a fresh check.
2. Submit one actual user action with `submitPracticeAction(attemptID:competencyID:commit:library:persist:)`. It accepts no credit or feedback flag. The host commits the user command, evaluates a supported anchor, and persists the session and first observation together. Failed persistence publishes neither. Competency order follows the versioned variant. Unsupported anchors record an observation with no credit value; they remain unknown in the fixed denominator.
3. Persist `revealPracticeFeedback(attemptID:actionID:coached:persist:)` before showing feedback. It cannot change the stored answer. Set coached for actual guidance, not VoiceOver, translation, alternate input or extra reading time. Coaching makes the attempt ineligible for score credit.
4. Use `compileScorecard(rubric:assessments:library:)`. It validates source identities and each capture receipt and replays the exact user-action prefix to derive grades. Caller scalar answers are ignored. An altered source, receipt or observed grade fails closed. Legacy imported attempts without capture provenance earn no practice credit; retain them as unverified history. Legacy incomplete records can resume as history/training. An explicit retest action may call archiveUnverifiedPractice before beginning a fresh source-bound check; every imported answer is retained. A source-bound attempt cannot be archived to evade a recorded error or reroll its variant.

New optional `PracticeAttempt.source` and `.observations` decode old Vault state without data loss. Capture stores no raw model deliberations or provider tokens. Keep the whole AI blob inside the existing encrypted local transaction. The Swift host's NDJSON `practiceBegin`, `practiceSubmit`, `practiceFeedback`, and `assess` with `aiState` exercise this same code. These local request/response bodies contain private state and must **not** be forwarded to the cloud.

Example local begin:

```json
{"op":"practiceBegin","session":{"...":"local serialized SimulationSession"},"attemptID":"check-1","variantID":"practice-check-a/0"}
```

Example submission, with the returned `aiState` preserved:

```json
{"op":"practiceSubmit","session":{"...":"same local session"},"aiState":{"...":"returned local state"},"attemptID":"check-1","competencyID":"initialResponse","commit":{"id":"submitted-input-1","actor":"user","baseRevision":1,"commands":[{"kind":"useStoredWater","value":"essential"}]}}
```

The returned observation has competencyID, actionID, acceptedRevision, receiptDigest, optional credit, and feedbackRevealed=false. Feedback request supplies attemptID/feedbackActionID; it changes only the feedback marker and optional coached status.

Run `pnpm --dir services/ai-orchestrator exec tsx scripts/practice-capture-eval.ts` after the Core build. `fixtures/ai/practice-capture.json` records a supported first answer plus three explicit unsupported attempts: practice 25, assessed 1/4, restored state, and a rejected changed grade. `PracticeCaptureTests` covers persistence rollback, resume/reroll prevention, unknown anchors, coaching, source/receipt tampering, untrusted legacy flags and fresh-session retesting. All 377 Core tests pass. These checks do not establish psychometric comparability or validate a complete four-competency examination. Existing anchors/variants remain provisional; native timing/UI, accessibility, human content review and wired-iPhone checks are pending.

Concern-seeded sessions are training/stress exercises, outside the current practice variants. beginPractice, submitPracticeAction and eligiblePracticeAttempts reject that relabeling. Use the ordinary educational debrief; no practice points are granted for arbitrary additional obstruction assumptions.

## Versioned adaptation anchors/2

New attempts persist `source.evaluatorVersion = "dryrun.practice-anchors/2"`; missing values select the original anchors/1 algorithm. Unknown versions reject at submission/eligibility boundaries. Source-bound scorecards include `practiceEvaluatorVersion`; history without a captured source retains its prior shape. Do not relabel old captures or regrade their observations with a new anchor.

The original adaptation anchor required no route before a move and a route afterward. A committed blockage can already have a computed alternate, so this left a valid response unassessed. Anchors/2 reconstructs prior committed receipts: a verified primary path from the same start/home must have been invalidated by current exclusions. Credit requires actual movement along a verified current primary/alternate, a verified movement path and verified resulting egress. A movement failing because of the scenario blockage earns zero; missing connectivity/verification stays unknown. Unchanged routes, same-room movement, arbitrary safe movement and shelter/refuge objectives remain unassessed. No reaction time, physical ability or model grade is used. See `content/ai/practice-anchors-v2.json`.

Run `pnpm --dir services/ai-orchestrator exec tsx scripts/practice-adaptation-eval.ts`. The retained `fixtures/ai/practice-adaptation-v2.json` contains the usual kitchen exit, committed kitchen blockage, host-computed living-room alternative and two actual user-action branches. The verified alternative earns one adaptation credit (25 practice points); the blocked attempt earns zero, with one assessed competency in each branch. Restore/replay is exact and source facts are unchanged. This is synthetic, offline anchor evidence, with no new Gemini calls. Core tests also cover no prior failure, incomplete connectivity, same-room attempts, legacy grading and unknown-version rejection. It does not establish variant comparability or a complete four-competency check. Native must preserve the evaluator version through Vault writes and show scope/version changes separately from earned improvement.
