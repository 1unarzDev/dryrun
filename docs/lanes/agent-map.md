# MapKit lane

Implemented the M1/M2 map lane in the shared checkout.

- `Maps/MapPlanningView.swift` is the full-size native SwiftUI MapKit flow. It has county framing, map/list parity, category filters, selection/detail sheets, source and freshness copy, Apple Maps search disclosure, explicit origin and transport-mode preview requests, ordinary-route wording, and an Open in Apple Maps action.
- `Maps/MapKitAdapters.swift` keeps `MKLocalSearch`, `MKDirections`, and optional Core Location permission behind app adapters. Help/map opening never requests location. Search and directions are cancellable and return plain values to the view.
- `Maps/MapModels.swift` provides stable namespaced selection IDs and `RegionalResourcesStore`. Bundled resources are immediate; validated refreshed packs override by resource ID while retaining statewide contacts and rejecting late county responses.
- Help now presents a prominent `Plan with Apple Maps` entry after immediate assistance access. The old 300-point directory map is no longer the primary journey.
- Public contracts accept optional validated coordinate provenance and region framing while remaining version-1 readable. Coordinates use `GeographicCoordinate`, separate from indoor metres. The Erath and Hood county office pins cite OSM objects S50/S51; map frames are documented approximate browsing context.
- Public pack validation rejects partial/out-of-range coordinates, missing coordinate citations, invalid region centers/spans, and source omissions. The service preserves coordinate citations when scoping a regional response.

Verification in this environment: `pnpm test` in `services/public-api` passed (4 files, 68 tests), and `pnpm typecheck` passed. JSON packs parse with Python and `git diff --check` is clean. Swift/Xcode, simulator, and physical-device checks were unavailable here; native MapKit, Apple search/directions, location permission, and private-place save/reopen still require the Mac/simulator/device verification lane.
