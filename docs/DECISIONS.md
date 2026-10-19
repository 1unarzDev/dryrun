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

8. **Personal households start without geometry (October 17 supersedes the fictional starter).** The vault explicitly distinguishes intentional absence from corruption. Family preparations/card work without a scan; example households are an explicit fictional path.

9. **Temporary PDF exports in the app temp dir** with complete protection + backup exclusion, purged on preview
   dismissal, app background, and delete-all. The vault also provides `makeExportFile`; unifying on it is in BACKLOG.

10. **Optional explanations gated to iOS 26 `FoundationModels` and English only.** Deployment target stays iOS 18.
    The model only rephrases a template; a conservative validator rejects new digits, safety verbs, and medical
    terms. Safety instructions and numbers never come from the model.

11. **Swift 6.2 language mode 6 / strict concurrency complete** in project.yml.

12. **No backend deployment.** Wrangler config is included without secrets; deployment is not authorized/provisioned.
    The app works fully offline from bundled content.

13. **"Mark preparation completed" is a record, not a model input.** The engine never reads it, so it does not bump
    the household revision or discard the on-screen rehearsal. Facts a preparation changes (for example, a confirmed
    backup) are edited through household setup, which does invalidate results.

14. **Captured story and actual exterior grade differ (October 17).** Scanned grade starts unknown and needs confirmation. Ground/above/below/walkout evidence gates discharge; no lowest-scanned-floor ground assumption. Legacy manual/sample behavior is preserved; scan imports use conservative explicit unknown grade.

15. **Prohibition styling comes from the source-language text**, so translated prohibitions keep their emphasis.
    An explicit per-key style marker would be more robust (BACKLOG).

16. **The draft-translation banner is bilingual**: the localized text plus the exact English phrase
    "Draft translation - language review pending".

17. **Adversarial cross-lane reviews.** Each lane was reviewed by an agent that did not write it:
    - privacy: B reviewed C and the lead
    - routing: A reviewed B
    - lead core: A
    - lead iOS: B
    - regional agent: A

    Findings and fixes are in `docs/lanes/review-*.md`.

18. **The regional agent ships with `UnavailableProvider`.** No model credentials are approved. The template brief
    is the working path, and model output can never be promoted to reviewed content automatically.

Lane-specific decisions are recorded in `docs/lanes/agent-a.md`, `agent-b.md`, `agent-c.md`.


## October 17 superseding product decisions

General family preparation is address-optional and outside the supported-region backend. No county-first setup,
foreign Texas fallback, device-only card requirement, or blanket ban on illustrative hazard states remains.
Family card selection applies across exports; routes/clinical facts remain deterministic and sourced. Public
region allowlists, encrypted local storage, iOS18 minimum and honest exercise uncertainty remain constraints.
Native proof is pending; source parsing is not SDK verification. Completion is subject/fingerprint scoped and
follows saved factual records, never a generic button certifying compatibility or an escape path.

## October 18 on-device language model decisions (owner request: tailor prep to each family with an LLM)

19. **Only Apple's on-device model, never a cloud model.** `SystemLanguageModel` (Foundation Models, iOS 26+ with
    Apple Intelligence) runs on the phone, works offline and costs nothing per family. The iOS 27 SDK's
    `PrivateCloudComputeLanguageModel` and third-party APIs were not used: household and medical facts would leave the
    phone, and an API key cannot be shipped safely in an app.
20. **The ranker still decides; the model explains.** Which preparations matter, their order, every number, route and
    instruction stay in DryRunCore (tested). The "For your family" card restates at most the top three steps. Inputs
    are built by `PlanBriefing` (enum-derived household facts; names, custom labels and contacts redacted; no notes,
    address or phone). Each sentence must pass `PlanBriefing.accept` (no new numbers, links, phone numbers, or
    clinical/certainty/time words, stem-matched in EN/ES); otherwise the authored text stands alone. Vietnamese has no
    validator yet, so the card is not shown in Vietnamese.
21. **Supersedes part of the ExplanationService rule** ("person names and clinical notes are never model inputs, even
    locally") for one feature only: "Describe your household". The family's own typed or dictated description is
    read on-device into an `IntakeProposal` of existing structured choices (age band, relationship, assistance
    needs, equipment purpose, pets, housing). The text is never stored; nothing is applied until the family reviews
    each item; nothing is marked confirmed; existing entries are never overwritten. Without the model (older phones,
    Apple Intelligence off, unsupported language) a tested EN/ES/VI keyword reader produces the same kind of proposal,
    so the feature works on every supported iPhone.
22. **County is chosen, not inferred.** Real households previously never received a region ID, so no county
    resources were reachable. A County picker (setup and Help) is the only way to set it; Apple place names are still
    not trusted as coverage. Tarrant County (48439) now has seven official resources (checked 2026-10-18,
    `needsReview`).
