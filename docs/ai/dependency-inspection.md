# Recorded access dependency inspection

`dryrun.dependencies/2` implements reference §11's recorded supply storage and destination conditions checks alongside existing route, helper, power, contact and transport checks. This is a read-only diagnostic, not a new score criterion or proof that the whole plan is robust.

New `SimulationSession` instances freeze `dependencyPolicy: "dryrun.dependencies/2"`. Decoded historical sessions with this property absent/null retain their prior kinds. Preserve the optional policy when copying/resuming a session, including inventory confirmation reconstruction. Stress and counterfactual operations propagate it. The existing strict five-field `DependencyInspection` wire shape is unchanged; the policy is portable source metadata and is not sent as private household evidence.

`dependencyInspection(receipt:library:)` now throws if the supplied receipt differs from the session's actual current query. Prefer `executeTool(.inspectDependencies)` from the native continuation handler. Stress checks inspect their executed baseline session with its actual inventory, rather than constructing a different empty session. Retests run the same schedule and do not mutate source inventory.

Example minimized observation (IDs and digest are illustrative):

```json
{"kind":"inspectDependencies","dependencies":[{"id":"storage|sp-kitchen","kind":"recordedSupplyStorage","subjectIDs":["food"],"evidenceIDs":["receipt-digest","sp-kitchen"],"status":"Recorded inventory only; access unavailable. Sole recorded location for 1 stock categories. Unknown quantities conditional; access loss cause unproven."}]}
```

A storage group only covers potentially nonempty recorded stock in a valid home space. Unknown amounts remain conditional; known zero records are excluded. Expiry, inaccessible confirmation, or a failed route can all make stock unavailable, so the observation does not attribute causation. Taking stock removes that item from its storage group and creates a current-carrier dependency. Missing or invalid room IDs are not invented. Destination review passes opaque IDs and typed condition state without labels, addresses or freeform provenance.

Linux tests: `scripts/swift.sh packages/DryRunCore test --filter SessionDependencyTests`. Full compatibility checks: `scripts/verify-ai-portable.sh`. No live Gemini call is needed for this deterministic host slice. Existing retained model traces must continue to replay under their frozen source policies.

Native checks remain pending: show only a few useful findings within Plan/debrief; label recorded-only and hypothetical scope, unknown access/capacity and unverified activation; test supply take/transfer, hazard and expiry refresh, stale continuation rejection, source edits and offline use on the wired phone. Do not create a separate dependency dashboard or let a diagnostic complete a real task.
