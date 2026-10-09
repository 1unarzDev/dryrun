# Shared contracts and ownership (frozen 2026-10-09, initial build)

Changes to anything in "Lead-owned" go through the lead. Additive fields are fine if you tell the lead;
renames/removals are not. Never edit another lane's files — ask the owner.

## Environment facts

- Host: Linux x86_64, no Xcode / iOS SDK. Swift 6.2 runs in Docker: `scripts/swift.sh <pkg-dir> <args>`.
  Set `DRYRUN_SCRATCH=<lane>` (lead / a / b / c) so lanes don't share build directories.
  Example: `DRYRUN_SCRATCH=a scripts/swift.sh packages/DryRunCore test --filter Simulation`
- iOS app code under `apps/ios/` can only be syntax-checked here (`swiftc -parse`), never compiled.
- Node 26 + pnpm on host for `services/public-api`.

## Directory ownership

| Path | Owner |
|---|---|
| `packages/DryRunCore/Package.swift`, `Sources/DryRunCore/Models/{Evidence,Household,Home,PublicData}.swift` | Lead |
| `Sources/DryRunCore/Models/Rehearsal.swift` | Agent A (after handoff; UI-facing names are stable) |
| `Sources/DryRunCore/Simulation/`, `Sources/DryRunCore/Ranking/` | Agent A |
| `Sources/DryRunCore/Spatial/` | Agent B |
| `Sources/DryRunCore/Plan/`, `Sources/DryRunCore/Content/` (except `PublicDataPolicy.swift`) | Lead |
| `Sources/DryRunCore/Content/PublicDataPolicy.swift` | Agent C |
| `Tests/DryRunCoreTests/Simulation*`, `Ranking*`, `Counterfactual*` | Agent A |
| `Tests/DryRunCoreTests/Spatial*`, `Route*`, `Geometry*` | Agent B |
| `Tests/DryRunCoreTests/Plan*`, `Content*`, `Fixture*` | Lead |
| `Tests/DryRunCoreTests/PublicData*` | Agent C |
| `packages/DryRunVault/` (whole package) | Agent C |
| `services/public-api/` | Agent C |
| `content/scenarios/`, `content/actions/`, `content/locales/en/{scenarios,actions}.json`, `fixtures/scenarios/` | Agent A |
| `fixtures/homes/` | Agent B |
| `fixtures/households/`, `content/manifest.json`, `content/locales/en/{common,plan}.json` | Lead |
| `content/sources/`, `content/regions/`, `content/locales/manifest.json`, `content/locales/{es,vi}/`, `content/locales/en/help.json` | Agent C |
| `apps/ios/DryRun/Spatial/` (RoomPlan adapter, dollhouse, 2D plan, home editor views) | Agent B |
| `apps/ios/DryRun/Services/Vault*.swift`, `apps/ios/DryRun/Services/Keychain*.swift`, `apps/ios/DryRun/Services/PublicAPI*.swift` | Agent C |
| Everything else under `apps/ios/`, `project.yml`, `docs/` (except lane notes) | Lead |

Each agent writes a short lane report at `docs/lanes/<lane>.md` (what is implemented, tested, partial).

## Identifiers

- Scenario IDs: `freeze-power-loss`, `heat-grid-strain`, `tornado`, `flash-flood`, `home-fire`, `water-outage`.
- Content version: `content/manifest.json` → `contentVersion` (initially `2026.10.0`). Scenario packs carry their own `version` (semver).
- Source IDs: `S01`…`S31` exactly as in the brief, in `content/sources/sources.json`. Additional sources: `S40+`.
- Action IDs: `act.<area>.<slug>` (e.g. `act.backup.confirm-medical-backup`). Defined in `content/actions/actions.json`.
- Rule IDs: `rule.<area>.<slug>`. Event IDs: deterministic, `evt.<scenario>.<slug>[.<subject>]`.
- Service IDs: `svc.grid`, `svc.heat`, `svc.cooling`, `svc.refrigeration`, `svc.wellPump`, `svc.water.supply`,
  `svc.water.safety`, `svc.wifi`, `svc.cellular`, `svc.handset`, `svc.roads`, `svc.device.<equipmentID>`, `svc.transport`.
- Resource IDs: `res.water.stored` (gal), `res.backup.<backupID>` (Wh), `res.handset.charge` (fraction 0–1 or hours), `res.food.days`.
- Fact IDs (explanation chains): dotted paths into the household/home, e.g. `housing.waterSource`, `housing.heatingNeedsElectricity`,
  `equipment.<id>`, `backup.<id>.setupConfirmed`, `transport.vehicles`, `supplies.storedWaterGallons`, `home.portal.<id>`, `person.<id>.needs`.
- Region IDs: Texas county FIPS (`48143` Erath, `48221` Hood, `48439` Tarrant, …) plus `tx-statewide`.

## Localization

- Locale packs: `content/locales/<locale>/<domain>.json`, flat `{ "key": "text" }`. Locales: `en`, `es`, `vi`.
- Placeholders: `{name}` style; values are supplied by `templateValues`. Numbers and units are formatted by code, not translated prose.
- Keys: `scenario.<scenarioID>.<...>`, `action.<actionID>.title|why|effect`, `plan.<...>`, `common.<...>`, `help.<...>`.
- `content/locales/manifest.json` records per locale+domain review state: `reviewed` | `draft` | `missing`.
  All AI-produced translations are `draft`. A missing key falls back to English **visibly** (the Localizer reports fallback).

## Core API surface the app uses (names are stable)

```swift
// Agent A
public struct ScenarioLibrary { static func load(from directory: URL) throws -> ScenarioLibrary; var scenarios: [ScenarioDefinition] }
public struct RehearsalEngine { init(library: ScenarioLibrary, planner: EgressPlanning); func run(_ input: RehearsalInput) throws -> RehearsalResult
                                func compare(_ baseline: RehearsalInput, applying: Intervention) throws -> RehearsalComparison }
// Agent B
public struct EgressPlanner: EgressPlanning { init(); func plan(_:in:) -> RouteResult }
public enum SampleHomes { static var ranch: HomeModel; static var all: [HomeModel] }   // fictional
public struct HomeValidator { static func validate(_ home: HomeModel) -> [HomeIssue] }
public struct ScanImport  { /* plain-struct input mirroring RoomPlan surfaces -> HomeModel proposal */ }
// Lead
public enum SampleHouseholds { static var all: [HouseholdProfile] }                  // fictional
public struct ContentLibrary { static func load(from root: URL) throws -> ContentLibrary }
public struct Localizer { func text(_ key: String, _ values: [String: String]) -> LocalizedText }
public enum PlanBuilder { static func build(...) -> PlanDocument }
// Agent C (DryRunVault package)
public actor HouseholdVaultRepository { load() / save(_:) / deleteAll() }
public protocol VaultKeyStore; public protocol FileProtectionApplying
public actor PublicPackStore  // atomic known-good cache for region packs
```

## Fixture IDs

- Sample home `home-sample-ranch` (single floor, two exterior exits: front door from living room, back door from kitchen).
  Space IDs: `sp-living`, `sp-kitchen`, `sp-hall`, `sp-bed1`, `sp-bed2`, `sp-bath`, `sp-closet` (interior closet; tornado candidate),
  exterior portals `pt-front`, `pt-back`; meeting point annotation `an-meeting`.
- Households: `hh-oak` (rural Erath, electric well, oxygen concentrator), `hh-lake` (Tarrant apartment, renters, no car, `vi`),
  `hh-pine` (Hood manufactured home, wheelchair user, gas heat with unknown blower dependency).
