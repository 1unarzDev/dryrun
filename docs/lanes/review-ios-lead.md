# Compile-correctness review: lead iOS files (Agent B)

**Scope:** `apps/ios/DryRun/{App,Rehearse,Home,Plan,Help,Settings,Services}/*.swift` (excluding Agent C's Keychain,
VaultFileProtection, and PublicAPIClient), `apps/ios/project.yml`, and `apps/ios/DryRunUITests/`.

**Method:**
- Read every file against my knowledge of the iOS 18 SDK and Xcode 26 / Swift 6.2.
- Cross-checked every `DryRunCore`/`DryRunVault` symbol the app calls against the package sources.
- Compiled reduced reproductions of the risky Swift 6 patterns with Linux Swift 6.2 (`-swift-version 6 -typecheck`).
- `swiftc -parse` on all edited files: passes.
- YAML parse of `project.yml`: passes.

**Limits:** no iOS SDK on this host. Nothing here is "compiled for iOS". Run `xcodegen && xcodebuild` on a Mac before trusting
any of it.

## Fixed (minimal edits, behaviour unchanged)

| File | Change | Why |
|---|---|---|
| `App/DryRunApp.swift` | `import UIKit` | `PrivacyShield` uses `UIWindow`, `UIApplication`, `UIWindowScene`. SwiftUI usually re-exports these on iOS, but the import is explicit and harmless. |
| `Home/HomeTabView.swift` | `import UIKit` | `UIApplication.openSettingsURLString` (same reason). |
| `Plan/PlanViews.swift` | `import UIKit`; `present(animated: true, completionHandler: nil)` | Uses `UIPrintInteractionController`/`UIPrintInfo`. The explicit `completionHandler` avoids depending on an imported default argument. |
| `Plan/PlanPDFRenderer.swift` | `@MainActor struct PlanPDFRenderer` | It is only called from a button action. Isolating it keeps `UIGraphicsPDFRenderer`, `NSAttributedString.draw`, and `UIFont` calls legal in Swift 6 whichever way the SDK annotates them. |
| `DryRunUITests/DemoJourneyUITests.swift` | `@MainActor` on the test class | `XCUIApplication`/`XCUIElement` are main-actor isolated in current SDKs. The target builds in Swift 6 mode (project-level `SWIFT_VERSION: 6.0`), so non-isolated test methods would not compile. |
| `DryRunUITests/DemoJourneyUITests.swift` | Vietnamese test uses the Vietnamese strings | The Lake household's locale is `vi`, so the button is "Tạo kế hoạch" and the draft label is "Bản dịch nháp - đang chờ duyệt ngôn ngữ". The English labels would never be found, so this was a runtime failure, not a compile error. |
| `project.yml` | UI-test target: `GENERATE_INFOPLIST_FILE: YES`, `TEST_TARGET_NAME: DryRun` | The test bundle had no Info.plist source. |
| `project.yml` | Moved `UIRequiredDeviceCapabilities: [arm64]` into `info.properties` | `INFOPLIST_KEY_*` build settings are ignored when XcodeGen writes a custom Info.plist. |
| `project.yml` | Excluded `Resources/DryRun.entitlements` from sources | Prevents it from being copied as a bundle resource. Signing still uses `entitlements.path`. |
| `DryRunCore/Spatial/HomeValidator.swift` (mine) | De-duplicate issues by `id` | `HomeTabView` uses `ForEach(issues)`. A scanned portal with two unknown sides produced two identical IDs. |

## Checked and fine

**Probe-verified on Swift 6.2** (reduced code in `/tmp/drprobe`):
- `VaultPrivateDataStore.load`: `do { try await repository.load() } catch { switch error { case .keyUnavailableWhileLocked … } }`
  infers `VaultError` across the actor hop.
- `CapabilityService`: `[weak self]` → `Task { @MainActor in self?.isOnline = … }` inside a `@Sendable` handler compiles.
- `if case .cached(let d) = freshness` on an optional enum.
- Memberwise initializers of views holding `@State private var x = …` are callable from other files
  (`HomeConfirmationView(home:onFinish:)`, `ManualHomeEditorView`, etc.).

**Concurrency:**
- `AppModel` (`@MainActor @Observable`, `didSet` on `locale`).
- `Task.detached` closures capture only `Sendable` values: `RehearsalEngine`, `RehearsalInput`, `ContentLibrary`, `Localizer`,
  `[PublicResource]`, and `URL`. I checked the conformances in core.
- `TemporaryExports.hasActiveExport` is `@MainActor static var` and is only touched from the main actor.
- `PrivacyShield.shared` is main-actor isolated.
- Static `let`s hold Sendable values (`Color`, `[String]`, tuples of `String`).

**API names:**
- `ContentUnavailableView` actions.
- `Button(_:systemImage:)`, `LabeledContent`, `.onChange(of:) { _, new in }`.
- `.sheet(item: $confirming)`: `HomeModel` is `Identifiable`.
- `.navigationDestination(isPresented:)`, `ShareLink(item: URL)`, `PDFView`/`PDFDocument(url:)`, `UIPrintInteractionController.canPrint(_:)`.
- MapKit `Map { ForEach { Marker(_:systemImage:coordinate:) } }` and `.mapStyle(.standard(pointsOfInterest: .excludingAll))`.
- `ISO8601DateFormatter.string(from:timeZone:formatOptions:)`, `UIGraphicsPDFRendererFormat.documentInfo`.
- `ProgressView(value:total:label:)`.

**ViewBuilder usage:** `let` declarations and `switch` inside `List`/`Section`/`Form` builders, and single-tuple closure
destructuring in `ForEach(groups(...), id: \.0) { type, items in }`.

**Core API calls:** every one resolves, including:
- `RehearsalCursor.revealed/advance/replace(result:)`
- `LatestRequestGate.begin/shouldApply/invalidate`
- `ContentLibrary.source/region/resources(forRegion:)`
- `PlanBuilder.build(…options:)`, `CapabilityPlan.make`, `ScanAvailability` (exactly 3 cases, so the switch is exhaustive)
- `HomeConfirmation.steps/apply`, `ConfirmationAnswer` cases and labels
- `PublicAPIClient.Freshness`, `AppModel.publicClient.refreshAlerts`

**FoundationModels:**
- `SystemLanguageModel.default.availability` with `.available` / `.unavailable(reason)`.
- `LanguageModelSession(instructions:)`, `respond(to:)`, `.content`.
- Gated by `#if canImport(FoundationModels)` plus `#available(iOS 26.0, *)`. This matches my SDK knowledge.

**XcodeGen:**
- `packages:` local `path`.
- `- package:` dependencies (product name = package name).
- `- sdk: RoomPlan.framework`.
- `type: folder` + `buildPhase: resources` for `content/`.
- `info.properties`, `entitlements.properties`, `bundle.ui-testing`, and the scheme test target.

## Uncertain (not changed; please verify on a Mac)

1. **FoundationModels linking on iOS 18.** The target deploys to iOS 18 but `import FoundationModels` (iOS 26 only) is autolinked.
   I expect the linker to weak-link it because every use is availability-gated. If launch fails on an iOS 18 device with a dyld
   error, add `- sdk: FoundationModels.framework` with `weak: true`. That entry only works with an Xcode 26 SDK.
2. **`SystemLanguageModel.Availability` exhaustiveness.** If the enum is non-frozen, the two-case `switch` warns without
   `@unknown default`. It is a warning, not an error.
3. **`com.apple.developer.default-data-protection`.** Needs the Data Protection capability on the App ID / provisioning profile,
   which automatic signing usually adds. Simulator builds are unaffected.
4. **`DryRunVault` resolves `swift-crypto` in Xcode.** The dependency is conditional on Linux, but Xcode still fetches it. The first
   resolve needs network access. Alternatively, move the Linux-only dependency behind an env-gated `Package.swift` branch.
5. **UI test selectors** (runtime, not compile):
   - `containing(.staticText, identifier: "Decision")` relies on XCUI matching the label. Add
     `.accessibilityIdentifier("decision-card")` to `DecisionCard` for a stable hook.
   - `app.cells.firstMatch` in the freeze test may tap the "your choices" row rather than a recommendation.
6. **Window exits via confirmation** (runtime semantics; a `LeadAdversarialTests` known issue).
   - `HomeConfirmation.markPortalExterior` sets `operable` confirmed and `verified` on a window. My planner then treats the window as
     an emergency exit by design: verified, operable, ground floor, and only for people who don't need step-free access.
   - Suggested fix in the lead's `HomeConfirmation`: never offer or apply the generic "leads outside" answer to windows. The view
     already hides the button for windows, but `apply` does not refuse. If a window should be an exit, use a separate explicit
     "everyone who would use this window can open it and climb out" answer.
7. **English draft notice.** The Vietnamese draft label is fully Vietnamese. Brief §15 asks plans to "visibly state 'Draft
   translation - language review pending'". Decide whether the English phrase must also appear alongside the translated one.
   This is a content decision for the lead.
