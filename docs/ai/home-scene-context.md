# Recorded safety facts in minimized home context

Reference §9 requires the actual home graph and safety-relevant verification, not an unlabeled screenshot. `HomeSceneContext(home)` now emits `dryrun.home-scene/2`. The host uses this same builder for its initial `homeScene` and read-only `inspectScene` tool. This is context for interpretation; deterministic routes, suitability, arithmetic and commits remain in Core.

The new version adds:

| Field | Meaning and boundary |
| --- | --- |
| `homeSource` | Existing sample/manual/RoomPlan source; no scan identifier, address or private label. |
| `floors[].level`, `.exteriorGrade` | Recorded level and grade; a missing raw grade is explicitly `unknown`, never inferred from story/elevation. Legacy host routing can retain its documented manual/sample compatibility rules; a context value is not a substitute route calculation. |
| `rooms[].geometryNeedsReview`, `.needsMeasurement` | Existing geometry review/measurement state. A room-use answer in the old `confirmed` field does not verify polygon geometry or a route. Missing historical geometryNeedsReview follows the existing Core `!= true` semantics when creating a fresh context. |
| `rooms[].interiorNoWindowsConfirmed`, `.higherRefugeConfirmed` | Actual evidence values with origin/status/source/input IDs; missing refuge evidence is unknown. An old affirmative answer is retained even when current facts invalidate its use. |
| `rooms[].confirmedShelter` | `ShelterSuitability.isConfirmed` under the same current source home. False means no currently confirmed suitable planning choice for this room, not proof that the household has no shelter. Neither true nor false is structural certification. |
| `portals[].emergencyEscapePersonIDs` | Only the existing explicit reviewed resident IDs, when recorded. A generic or historical emergencyEscapeConfirmed Boolean is not promoted to person-specific access. Width, operability, step-free evidence and portal verification remain separate. |

The strict TypeScript `scene` union accepts separate /1 and /2 shapes; unknown versions reject. /2 requires the new floor/room facts and home source, with the resident-ID list optional to retain unknown versus explicitly empty. Optional Swift fields decode historical /1 payloads without inventing new evidence. Do not relabel or enrich saved model inputs while replaying them. `content/ai/contracts/homeScene-v1.schema.json` is the version-1 transport schema supporting both payload versions; the containing director/feature/continuation schemas use the same union.

Private home/floor/room/obstacle/object labels, portal/annotation notes, original scan-room IDs and saved-place coordinates are excluded. Graph IDs, per-floor transforms, geometry, connector verification and existing evidence survive. This remains sensitive home data and still requires native cloud consent. It never authorizes forwarding a full HomeModel, map result, photo collection or raw local host response.

Native integration: use the builder, not a hand-created subset. Forward only the strict minimized context; retain its identified initial home snapshot while a session runs. Read actual affected rooms/portals and current route outcomes from receipts/tool previews. After real home edits, invalidate pending proposals and explicitly fork or continue against the original source. Do not overwrite geometry, room confirmation, marker verification or recorded grade from model observations. An image box never establishes a usable opening or shelter. Existing Home and Rehearse remain the presentation owners.

Run after the Core build:

```sh
pnpm --dir services/ai-orchestrator exec tsx scripts/home-scene-eval.ts
```

`fixtures/ai/home-scene-v2.json` contains four synthetic actual-host source sessions, contexts, read-only interior-shelter route requests/results and receipts. Current confirmation permits the route; unknown grade, pending geometry review or proposed shelter marker removes it. The original affirmative room answer remains visible. The script checks strict TS acceptance of actual Swift output, read-only receipts, private-label/note exclusion, and old/unknown/malformed version handling. Core tests also check JSON restoration, the historical /1 fixture and person-specific escape metadata. This command is included in portable verification.

These are host/schema tests with no new Gemini calls. Model use of the extra facts has not been freshly evaluated. RoomPlan capture, real safety-attribute review, native lifecycle/consent/overlays and human safety/language/household review remain pending. Do not present a context Boolean as a route or safety guarantee.
