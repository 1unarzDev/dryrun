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
