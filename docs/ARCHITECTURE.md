# Architecture

## Modules

```
apps/ios/DryRun/                SwiftUI app (iOS 18+). Thin: views, adapters, platform services.
  App/                          AppModel (@Observable, run-ID guarded async work), RootView (Prepare / Rehearse / Plan), Theme
  Rehearse/                     Scenario picker, stepped timeline, decision cards, debrief, before/after comparison
  Home/                         Home tab, progressive household setup
  Spatial/            (Agent B) RoomPlan capture adapter, 2D floor plan, RealityKit dollhouse, room list, manual editor
  Plan/                         Plan viewer, Core Text PDF renderer, PDFKit preview, share/print
  Help/                         Sourced directory, NWS alerts section, optional MapKit view
  Services/                     Content locator, capability checks, temp exports, optional on-device explanations,
                                PrivateDataStore bridge → DryRunVault; Keychain/file-protection/public-API adapters (Agent C)
  Settings/                     Language, privacy explanation, capability status, delete-all

packages/DryRunCore/            Foundation-only Swift package (no SwiftUI/RoomPlan/RealityKit/MapKit/CryptoKit/simd)
  Models/                       Shared contracts: EvidenceValue, HouseholdProfile, HomeModel, route contract,
                                rehearsal/recommendation contract, public data types
  Simulation/         (Agent A) ScenarioLibrary, dependency model (AND/OR), backup allocation, hazard rules,
                                discrete-event RehearsalEngine, interventions, counterfactual compare
  Ranking/            (Agent A) Action catalog, lexicographic RecommendationRanker
  Spatial/            (Agent B) Geometry, HomeValidator, EgressPlanner (verified portal graph + Dijkstra),
                                RouteCache, ScanImport (plain RoomPlan mirror → proposed HomeModel), SampleHomes
  Plan/                         PlanDocument, PlanBuilder, PlanValidator, WaterTarget
  Content/                      ContentLibrary, Localizer (visible fallback + review state), SampleHouseholds,
                                PublicDataPolicy (Agent C: alert freshness, activation display, region allowlist, query builder)

packages/DryRunVault/ (Agent C) Encrypted vault (AES-GCM via CryptoKit; swift-crypto only on Linux for tests),
                                VaultKeyStore / FileProtectionApplying protocols, HouseholdVaultRepository actor,
                                PublicPackStore (atomic known-good public cache)

services/public-api/  (Agent C) Hono + Zod on Cloudflare Workers. Public data only. No household endpoints.
content/                        Versioned bundled content (scenarios, actions, locales, sources, regions)
fixtures/                       Fictional households, homes, expected scenario outcomes
```

## Data flow

```
 household (vault) ─┐
 home model (vault) ─┼─► RehearsalInput (immutable snapshot + scenario/content versions + seed + choices + interventions)
 scenario pack ─────┘            │
                                 ▼
                       RehearsalEngine.run  ──► DependencyModel (AND/OR, bounded fixed point)
                                 │              BackupAllocation (no double-allocated energy/output)
                                 │              EgressPlanner (fire: authored exclusions → typed route results)
                                 ▼
                       RehearsalResult (events, snapshots, decisions, routes, recommendations, unknowns)
                                 │
         ┌───────────────────────┼─────────────────────────────┐
         ▼                       ▼                             ▼
  Rehearse UI (cursor)   compare(baseline, intervention)   PlanBuilder → PlanDocument ─► viewer / PDF / vault
                         → RehearsalDiff (baseline untouched)
```

Everything left of the vault boundary runs on-device. AppModel runs simulation, comparison, and plan building in
`Task.detached`, tags each request with a run ID, and discards any result whose run ID or household/home revision
is no longer current, so a late result can never overwrite newer state.

## Two distinct graphs

1. **Dependency model** (Simulation/): services, devices, resources, requirements and alternative supplies with
   AND/OR semantics (e.g. oxygen concentrator requires power; power = grid OR a *confirmed compatible* backup).
   Service availability and resource depletion are tracked separately.
2. **Egress graph** (Spatial/): metric 2D per floor; nodes are spaces/portals; edges carry real polylines,
   verification, operability, clearance, step-free evidence, and scenario exclusions. Hard exclusions apply before
   Dijkstra. Alternatives must use a different exit and avoid the primary route's chokepoints.

Fire, flood, and tornado share deterministic spatial exercise snapshots. The engine supplies authored exclusions and explicit outdoor-egress, interior-shelter, or higher-refuge destinations; the same validated graph serves each purpose.

## Private / public boundary

| Private (vault only, encrypted) | Public (may be fetched/cached) |
|---|---|
| HouseholdProfile, HomeModel, scans, rehearsal results, retained plans, completed preparations | Region packs, NWS alerts, FEMA context, source manifest, content packs |

- No household endpoint exists. The public client builds URLs only through `PublicQueryBuilder`
  (allowlisted endpoints and region IDs; rejects unexpected keys). The backend also rejects unknown query keys and bodies.
- Address search, nearby discovery, snapshots and directions use Apple adapters. Home confirmation starts bounded nearby discovery; current GPS is requested only by its control. These inputs never go to the public DryRun service.
- Plaintext leaves the vault only for an explicit PDF preview/share/print; temporary exports are protected,
  excluded from backup, and purged on dismiss, background, and delete-all after active share/print leases finish.

## Adapter interfaces (platform seams)

| Protocol / type | Core or Vault side | iOS implementation |
|---|---|---|
| `EgressPlanning` | DryRunCore | `EgressPlanner` (pure) |
| `VaultKeyStore` | DryRunVault | `KeychainVaultKeyStore` (kSecAttrAccessibleWhenUnlockedThisDeviceOnly) |
| `FileProtectionApplying` | DryRunVault | `IOSFileProtection` (complete protection + excluded from backup) |
| `PrivateDataStore` | app | `VaultPrivateDataStore` (maps VaultError → locked / needsRecovery) |
| `ScanImport` input structs | DryRunCore | RoomPlan adapter maps CapturedRoom/CapturedStructure surfaces |
| `ExplanationService` | app | Optional `SystemLanguageModel`; template fallback always available |

## October 17 family-preparedness integration

Personal household identity is independent of geometry: `HouseholdProfile.homeID/stableHomeID` links places and
plans before a scan exists. `PrivateSnapshot.home` is optional. Vault schema 1 adds an explicit
`homeGeometryIntentionallyAbsent` flag; legacy missing layout remains a recovery condition, distinct from a
successfully saved layoutless household. Additive optional fields preserve old contacts/custom labels/places.

`AppModel` publishes candidate snapshots only after private saves succeed and excludes overlapping writes.
Completion and generated plans follow that transaction rule. Async generations carry epochs/revisions. A prior
saved scenario plan is retained as labeled stale history; `currentPlan` rebuilds the live card from current facts.

`BaselinePreparedness` merges household/home facts with deterministic scenario gaps before any rehearsal.
Recommendation identity is action plus explicit subject; `PreparationCompletion` fingerprints only relevant
records. Factual tasks follow saved facts, physical checks require recorded evidence. Device electrical support
and medicine cold storage are independent; ownership never confirms compatibility or runtime.

`FamilyEmergencyCardBuilder` supplies every household's selected-content card, including no medical equipment or
home. `PlanBuilder` accepts optional geometry and saved places. Its plain visual snapshot contains canonical
layout, exact qualified route legs, place records and revisions. App-layer adapters render native PDFs and
transient attributed Apple snapshots; Core has no MapKit/UI dependency. Linked outside meetup annotations have
`savedPlaceID`; geographic coordinates never become indoor metres.

`SpatialExerciseState` is the stage/person/seed contract for routing, 2D, 3D and export. Current routes are separate
from snapshot history. Floor capture story is separate from confirmed grade; scan lowest floor is not ground.
`CaptureCallbackGate` identifies the originating capture generation. Native SDK and physical coordinate validation
remain pending; see CLAUDE_NATIVE_HANDOFF and VERIFICATION.

Locales use the existing versioned content Localizer, extended with native/spatial domains. Stable model IDs stay
untranslated; user names, addresses and critical notes are retained. ES/VI strings remain drafts requiring human
review. No optional automatic clinical translation or default reminder campaign was introduced.


Follow-up correction contract: `HomeGeometryEditor` applies transactional shape-preserving room resize/move,
explicit opening placement and two-floor stair landing edits. First capture polygons/walls remain provenance.
Independent or ambiguously owned captured walls remain physical barriers; only exclusive old room-boundary
segments are replaced. Dynamic outline walls are derived per render, never cached as captured walls. Corrected
rooms stay outside routing until reviewed; openings/stairs have separate evidence. Adding/removing rooms cannot
silently remove another room's barrier. `ShelterSuitability` is shared by confirmation, planner and simulation;
current grade, lowest level, windows, selection and room review must agree.

`PreparationFact.applyingEdits` invalidates physical checks/coverage/location awareness when availability or
location changes, retaining note-only edits and later explicit checks. Home geometry changes clear only the
escape-check date. Solo card review and optional joint family review have separate additive dates. The deterministic
baseline accepts an injected reference date for maintenance, with no default notification scheduling.

`ReviewReminderScheduling` and `ReviewNotificationAccess` isolate a one-time, explicitly selected local reminder.
The shared scheduler invalidates suspended authorization/add operations when canceled or private data is deleted;
failed deletion leaves existing data/reminders intact. Payloads contain only generic localized app text. This native
boundary has authored fake tests but has not been compiled or executed against UserNotifications here.

The connected-flow follow-up adds plain PreparationEditTarget (exact factual editor/subject), PreparationDraft
(only deliberate supply ownership changes), and FamilyPlanExportRequest (immutable selections, no older-plan
fallback). generatePlan returns the successfully persisted candidate; callers export that value. Place-order
staleness is normalized in the core. MapRoutePreviewModel owns cancellable GPS/directions generations. Shared
HomeScenePresentation supplies renderer/list status and floor/start/selection geometry without deciding routes.
RehearsalDiff resolvedRecommendations now carries exact recommendation IDs, preserving subject context.
ContactRole.waterUtility is additive; old enum values and household data are retained. Public coverage is the
explicit bundled county/aggregate set; a Texas-shaped number alone does not establish coverage.

## Selected language and measurement follow-up (October 17)

The existing Localizer remains the single text bridge. selectableLocales requires every bundled English domain/key, nonempty strings and matching placeholders; it does not promote AI drafts to human-reviewed content. UI pickers, default marker labels, Help, scan review and rehearsal clocks use stable IDs and selected-language strings. Personal notes/proper names stay exact. FamilyEmergencyCard and PlanBuilder share provenance tracking; card fallback/draft notices and source IDs reach the document. Validation exposes localized privacy-preserving descriptions separately from diagnostic IDs.

PlanningMeasurements formats Apple distance/time estimates and canonical-US-gallon water values for display only: US water uses gallons, other/unknown countries litres; map distances use miles for US/GB and metric elsewhere. Recommendation/event presentation, comparisons and full-plan water lines share this conversion. The deterministic engine, evidence values, indoor metres and saved facts are unchanged. Explicit CA emergency-number lines cite S56; unknown/unsupported countries retain the local-number prompt, with no public-region substitution.

## Connected data and scene contract follow-up

RehearsalInput and run state accept intentionally absent geometry. All six exercises can still assess household
continuity/decisions; absent geometry supplies no route, floor, shelter or invented scene. Optional applicability
requires evidence: missing layout satisfies neither hasStairs nor its negation.

HomeRoomAssociations remaps resident assignments only from retained manual identity or originating capture
room/frame lineage. Ordinal collisions in unrelated rescans clear the assignment. Space.sourceScanRoomID and
HomeModel.sourceCaptureFrameID are additive provenance. Window escape suitability is explicitly person-scoped;
the legacy Boolean alone authorizes nobody. Helper reach uses canonical geometry/portals/mobility routing.

MedicalBackupReadiness and TransportReadiness share recorded support requirements between preparedness, cards,
plans and allocator outcomes. BaselinePreparedness.recorded exposes tangible satisfied preparations with direct
review links; it does not persist synthetic Done records or create a safety percentage.

Plan schema 2 retains canonical final exercise exclusions, per-person results and shared PlanHomePanel
descriptors. Preview and PDF draw the same primary/alternative legs and hazard state on every relevant floor,
including no-route/start/destination/exposure floors. Selected export reuses a matching real rehearsal's recorded
seed, origin, starts, choices and leak variant; hypothetical comparison inputs cannot become actual plan facts.
Old schema-one documents remain readable but stale. Engine/route versions are cascade-engine/2 and
egress-portal-graph/2. Local leaks have separate content/events from regional flood exercises.

PlanMapSelection prioritizes near/backup meetup coordinates ahead of optional resources while retaining text
ordinals. Official and Apple records share destination actions; optional source/contact/check metadata is
persisted privately. HomeLocationChange distinguishes harmless unit/no-op corrections from geographic changes.

## Latest integration seams and handoff

HouseholdEditing prepares focused deletion/reference cleanup; AppModel commits the household and affected
window-person associations transactionally. PlanMapSelection/PlanMapExtent and PlanPlacePresentation share
near/distant extents, numbering, retained resource provenance and missing-snapshot reporting across phone and
export. MapKit responses are consumed inside documented main-thread callbacks before plain values resume
async callers; no global Sendable override was added. NearbyDiscovery's task-group closure still fails the
installed SDK build at Maps/MapKitAdapters:193 (see VERIFICATION). An explicit DEBUG simulator-only UUID
namespace permits real encrypted file/Keychain UI relaunch tests without touching the normal vault.
Content2026.10.2 invalidates older retained plan content. These seams require full native verification.
The complete owner goal and Claude continuation prompt govern the next pass; this is not a completion record.
