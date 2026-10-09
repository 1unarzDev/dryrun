# Architecture

## Modules

```
apps/ios/DryRun/                SwiftUI app (iOS 18+). Thin: views, adapters, platform services.
  App/                          AppModel (@Observable, run-ID guarded async work), RootView (4 tabs), Theme
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

The fire scenario is the only place they meet: the engine passes authored blocked spaces/portals to the planner.

## Private / public boundary

| Private (vault only, encrypted) | Public (may be fetched/cached) |
|---|---|
| HouseholdProfile, HomeModel, scans, rehearsal results, retained plans, completed preparations | Region packs, NWS alerts, FEMA context, source manifest, content packs |

- No household endpoint exists. The public client builds URLs only through `PublicQueryBuilder`
  (allowlisted endpoints and region IDs; rejects unexpected keys). The backend also rejects unknown query keys and bodies.
- Exact address/location stays local; geocoding/directions through Apple only on explicit user action (future).
- Plaintext leaves the vault only for an explicit PDF preview/share/print; temporary exports are protected,
  excluded from backup, and purged on dismiss, background, and delete-all.

## Adapter interfaces (platform seams)

| Protocol / type | Core or Vault side | iOS implementation |
|---|---|---|
| `EgressPlanning` | DryRunCore | `EgressPlanner` (pure) |
| `VaultKeyStore` | DryRunVault | `KeychainVaultKeyStore` (kSecAttrAccessibleWhenUnlockedThisDeviceOnly) |
| `FileProtectionApplying` | DryRunVault | `IOSFileProtection` (complete protection + excluded from backup) |
| `PrivateDataStore` | app | `VaultPrivateDataStore` (maps VaultError → locked / needsRecovery) |
| `ScanImport` input structs | DryRunCore | RoomPlan adapter maps CapturedRoom/CapturedStructure surfaces |
| `ExplanationService` | app | Optional `SystemLanguageModel`; template fallback always available |
