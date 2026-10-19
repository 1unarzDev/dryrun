# Director policy and scene actions

Reference section 10 governs this slice. New native exercises should call:

```swift
let session = try SimulationSession.initialize(
    id: sessionID, initial: input, library: library,
    inventory: SessionInventorySeed(ledger: confirmedLedger, asOf: referenceDate))
```

This freezes `DirectorPolicy.reviewed(scenario)` into the session. The name refers to host-known pack/rule bounds; the existing content remains draft and needs the independent human review described in `human-review-protocol.md`. No physical spread model or emergency timing is certified. The policy is included in the context digest and persisted/replayed with the source. Decoding old sessions without a policy preserves their legacy behavior; fork an old session to use the new commands rather than replacing its source or policy during resume.

Policy version `dryrun.director-policy/1` includes permitted primary hazard families, maximum active spatial incidents, scheduling horizon, total scheduled-event budget, pending-event budget and allowed spatial-stage transitions. Current engine capacity is **one spatial incident**; limits above one are rejected. Power/water/communications/roads conditions can compose within that incident's scenario pack. Arbitrary simultaneous fire/flood/tornado layers and cross-pack profile composition are not implemented. A family allowlist does not unlock profiles from another scenario.

Defaults allow at most 32 scheduled events, 8 pending events and the shorter of the pack horizon/4320 minutes. The host can restrict these limits. Profiles cannot repeat, occur in the past, exceed the horizon, bypass applicability, or violate the time-ordered transition graph. Graph nodes are **profile IDs**, not generated event-instance IDs. Supported starting stages can begin the incident; later stages can skip ahead through permitted forward edges. No stage is mandatory. Pending compositions are validated in `(minute, authored priority, profile ID)` order, including when submitted out of chronological order. Resource depletion takes precedence over incidents at the same minute.

`DirectorRuntimeState` exposes activeIncidentCount, scheduledEventCount, optional stageID/originSpaceID and optional lastWait. `DirectorProfileDescriptor` supplies id/rule/minute/hazard/spatial/canStart/roomRequired. The descriptor's minute is the pack's authored reference, not an automatic schedule. Send policy, runtime state, descriptors, pending commands and closedPortalIDs in the minimized director context; all are strictly validated. The gateway never changes the stored policy.

| Director command | Required fields | Host effect |
| --- | --- | --- |
| schedule | target profile ID, minute | Queue a supplied external/profile effect; spatial legacy adapter still enforces the policy graph |
| startIncident | target starting spatial profile, hazard, minute; value room ID for fire/flood | Queue one assumed incident in recorded geometry |
| advanceIncident | target later spatial profile, hazard, minute | Queue a permitted next stage, preserving the origin |
| advance | minute | Advance until requested time or an earlier mandatory resource/expiry boundary |
| waitUntil | target host predicate, durationMinutes | Advance within a finite window; report the actual stop reason |
| requestDecision | kind only | Pause for submitted user intent |
| finish | kind only | Finish without refilling stock or changing household facts |

Fire/flood origins must be actual room IDs. Fire's initial assumed room can be selected independently of its usual example room kind; later topology progression still uses implemented neighboring-room rules. The director cannot fabricate room coordinates, exits or affected portal sets. A regional tornado warning accepts **no indoor origin** and cannot choose a new household shelter; the host uses recorded shelter suitability. Flood/local-leak applicability and floor/route exclusions retain their existing distinctions. The scene routes returned for policy sessions are synchronized with current committed occupant routes, including after a move.

A spatial preview must include the incident **and** its application time:

```json
{"commands":[
  {"kind":"startIncident","target":"evt.home-fire.fire-origin","hazard":"homeFire","value":"sp-kitchen","minute":1},
  {"kind":"advance","minute":1}
]}
```

`evaluateCandidateAction` accepts exactly one `command` or `commands` (1–8), never both. Spatial previews require a following advance reaching the scheduled incident time. They return the minimized snapshot plus `preview` with current route ID sequences, optional spatial hazard/stage/origin/affected IDs and director state. Host depletion may still stop before the requested scene time; inspect the actual result. These are hypothetical results, never real facts or commits. The gateway provides at most one schema/semantic repair, paired to the original function call ID, within the existing four-call/90-second limit. After a successful preview, tools are disabled and the model must return a final proposal. Required fields are encoded per command kind; provider schema conversion preserves union alternatives. Known household-subject and home-element IDs can be cited, but a recognized ID alone does not prove a free-text claim. Render the final host receipt as authority.

Wait predicates are finite domain operations:

- `nextIncident`: satisfied by actually applying a queued incident, rather than merely reaching a minute.
- `storedWaterUnavailable`: known accessible stored water is zero and tap water is unusable; unknown stock is not satisfaction.
- `primaryContactChannelUnavailable`: the modeled handset or cellular service is explicitly unavailable; unknown service is not satisfaction, and alternative channels may still exist.

`lastWait` includes predicate, startedMinute, maximumDurationMinutes, stoppedMinute, satisfied and reason (`predicate`, `mandatoryBoundary`, `policyHorizon`, `durationLimit`). An unrelated depletion/expiry can interrupt the wait without satisfying it. Network latency never consumes simulated time.

User `closeDoor` takes target portal ID and value person ID. It requires a verified, operable door adjoining that person's actual current room, with no modeled blockage at that room/portal. `SessionReceipt.closedPortalIDs` is simulated posture only. A closed **operable** door remains a passable route; no spread delay, thermal protection or practice credit is inferred. Source HomeModel/household remain unchanged. The director cannot commit this user action. Use scene selection/one concise action in Rehearse, not a new agent flow.

Linux checks include `DirectorPolicyTests`, `SessionPacingTests`, provider schema/gateway tests and `scripts/spatial-policy-eval.ts`. Set `DRYRUN_LIVE_SPATIAL=1` for the separate synthetic live-Gemini trace. Test the native policy factory, batch continuation, chosen origin overlays, invalid/stale proposals, short waits/unknowns and door interaction on the wired phone. Independent content review and real-device usability remain pending.

`requestDecision` is a real pause: it must be the final command in its commit, sets `awaitingUserAction`, and blocks further director effects until a user action/attempt is committed. The gateway returns `needs_user_action` with the source binding without calling Gemini while that flag is set. Local fallback can keep the same pause; it cannot consume resources. A user can explicitly end via a user-owned `finish` commit. Use a single decision control in the existing scene, not a transcript or another confirmation sheet.

Completed proposals use `dryrun.director-proposal/1`: id, requestID, actor, baseRevision, full binding, commands, purpose, evidenceIDs, assumptionIDs, nextBoundary and presentationIntent. The envelope is compiled from the validated model commands; nextBoundary describes a **requested** minute/window, not a promise that the host reaches it. Its presentation intent is sceneFirst, renderFrom=committedReceipt and narration=unverifiedProposal. Core validates the embedded binding/metadata before committing. Legacy envelopes without a version retain the old decoder. `directorCommit` in the NDJSON harness exercises the same `DirectorProposal.commit(to:binding:library:persist:)` call that native integration should use. Do not pass full sessions to the cloud.

New exercise action feedback is in the `ai` locale domain for EN/ES/VI, all draft, under content version `2026.10.3`. Existing language-selection completeness checks remain in place; no source safety text was relabeled as human reviewed. The director runner records its prompt version and SHA-256 in evaluation metrics so future traces identify the exact instruction text.

Authored offline API: RehearsalEngine.run is an adapter through SimulationSession.authoredResult. Its ordered default-choice schedule calls the same SessionTransitionReducer initialization/time/event/depletion operations as incremental sessions; defaults remain exclusive to authored mode. Custom planner/action injection and event/depletion snapshot cadence are preserved. Twenty-four frozen pre-adapter result hashes cover both households and all six hazards with default/alternate choices. Minimized snapshots now include optional firedEventIDs so a director can distinguish applied profiles from available templates; an external profile uses schedule, never startIncident.
