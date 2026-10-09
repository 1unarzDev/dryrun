# Decisions, deviations, and assumptions

Each entry: decision → reason → consequence. Material deviations from the brief are marked **DEVIATION**.

1. **Linux build host; iOS code authored, not compiled.** The available machine is Linux without Xcode. The
   Foundation-only packages and backend are built and tested (Swift 6.2 in Docker; Node 26). iOS files are only
   syntax-parsed (`swiftc -parse`). → Every native integration is labeled PARTIAL/authored in VERIFICATION.md
   until compiled on macOS.

2. **XcodeGen `project.yml` instead of a committed `.xcodeproj`.** A hand-written pbxproj cannot be validated here
   and is merge-hostile. → One extra setup step (`brew install xcodegen && xcodegen`). **DEVIATION** (minor).

3. **Vault in a separate package (`DryRunVault`).** Keeps DryRunCore free of CryptoKit as required. The vault uses
   CryptoKit on Apple platforms and apple/swift-crypto *only on Linux* so the encryption, tamper, and atomic-write
   behavior can be tested on this host. swift-crypto is API-compatible and Apple-maintained. → The dependency is
   resolved (not linked) on iOS builds.

4. **Scenario semantics in Swift, timing/choices/exclusions in versioned JSON.** Rule IDs in packs map to audited
   Swift rule implementations; packs cannot introduce new behavior. → Content updates cannot change safety logic
   without an app release; this is intentional until signed content updates exist.

5. **One localization system for plan and safety text: versioned JSON locale packs + `Localizer`.**
   **DEVIATION** from String Catalogs for this content: review state per locale/domain, visible English fallback,
   and identical text in viewer and PDF are easier to guarantee with one resolver that the core package (and tests)
   can use. App chrome strings partly go through the same packs; remaining hard-coded English UI chrome should move
   to a String Catalog in the design pass (BACKLOG). Plural rules are not yet handled by the packs.

6. **All AI-written content is `draft`, including English safety text.** No human expert or language review has
   occurred. Every plan carries "Prototype safety content - expert review pending"; ES/VI additionally carry
   "Draft translation - language review pending".

7. **Phone exercise assumptions.** Handset runtime defaults to an explicit exercise assumption (18 h) labeled
   `.assumed`, never presented as a measurement.

8. **New households start with the fictional sample home** until the user builds or scans their own, labeled
   "Sample home (fictional)". → Avoids a blank Home tab; must not be mistaken for the user's home (labeled).

9. **Temporary PDF exports in the app temp dir** with complete protection + backup exclusion, purged on preview
   dismissal, app background, and delete-all. The vault also provides `makeExportFile`; unifying on it is in BACKLOG.

10. **Optional explanations gated to iOS 26 `FoundationModels` and English only.** Deployment target stays iOS 18.
    The model only rephrases a template; a conservative validator rejects new digits, safety verbs, and medical
    terms. Safety instructions and numbers never come from the model.

11. **Swift 6.2 language mode 6 / strict concurrency complete** in project.yml.

12. **No backend deployment.** Wrangler config is included without secrets; deployment is not authorized/provisioned.
    The app works fully offline from bundled content.

Lane-specific decisions are recorded in `docs/lanes/agent-a.md`, `agent-b.md`, `agent-c.md`.
