# Current source reconciliation and architecture decision

Inspected base `26332de`, current working changes tracked in ledger. No replacement stores or parallel UI architecture.

**Reconciliation correction:** the table below describes root `main`, not the complete local repository. Local branches `worktree-wired-iphone-pass` (`a9efc8f`) and `dryrun-six-hazard-continue` (`5f95135`) contain completed native work missing from root main. They diverge at `b2059be`; neither tip supersedes the other. Commit/path metadata identifies adaptive practice, scorecard, inventory, App Attest, hazard mechanics, resource discovery and sample/private-vault separation. Source clearance and semantic integration are in progress. Entries marked missing below are root-main gaps, not authorization to reconstruct those features. Original branches remain intact; current engineering changes have a separate pre-reconciliation checkpoint.

| Area | Actual source / symbols | Retain / extend / gap |
|---|---|---|
| Native target | apps/ios/project.yml; DryRun scheme, iOS 18+, Swift 6 | Regenerate existing XcodeGen project; stale generated membership omitted existing intake/briefing files. |
| Native state | App/AppModel.swift; LatestRequestGate; RevisionKey | Retain transaction-before-publication and request gates. Native integrated provider UI is missing, despite portable backend work. |
| Persistence | Services/PrivateDataStore.swift; VaultPrivateDataStore.swift; DryRunVault/VaultModels.swift | Existing encrypted payload already supports opaque integratedAIState. Native bridge previously dropped it on load/save. Extend bridge and central save preservation, explicit reset/switch clears state. |
| Intake/briefing | Services/IntakeAssistant.swift; FamilyBriefingService.swift; Home/DescribeHouseholdView.swift | Existing implementations retained, source membership restored. |
| Server runtime | services/ai-orchestrator/src/provider.ts, gateway.ts, features.ts, server.ts | Existing Gemini provider, validation/tool loop and typed gateway retained; Codex adapter behind AgentProvider under specialist ownership. |
| Public research | services/public-api/src/agent and existing official evidence services | Public-only boundary retained; arbitrary grounded research capabilities need real verification. |
| Rehearsal | Simulation/RehearsalEngine, HazardRules, IncrementalSession, SessionTransitionReducer | Authored native path and adaptive portable session are distinct; preserve early adaptive intent and authoritative practice evaluation. Applicability and causal gaps audited. |
| Assessment | Ranking/PracticeEvaluator, PreparednessScorecard, PracticeCapture; Models/IntegratedAIState | Fixed evidence scores retained; native flow/integration remains incomplete. |
| Families | Content/SampleHouseholds.all; HouseholdSetupView; App/DemoLaunch | Actual IDs hh-oak, hh-lake, hh-pine. Demo launch uses in-memory store. Native full matrix pending. |
| Homes | Spatial/HomeGeometryEditor, EgressPlanner, ScanImport, SampleHomes; native Spatial views | Existing stable IDs, graph and RoomPlan adapter retained. Direct selection/edits and durable Save require physical review. |
| Maps | native Maps; PlanMapPresentation, HomeMeetingPlaces, ResourceStrategyRefresh | Existing Apple geography and home graph remain separate. No exact exit coordinate inferred from address. |
| Native design | App/Theme.swift; SectionCard, status/button styles | Existing spacing/color components retained. Real reviewer-cleared iPhone evidence required before layout claims. |

## Decision

Mac/iPhone integration is the primary workflow. The plugged-in iPhone 16 Pro is the required native acceptance destination per owner steering. Portable tests supplement physical acceptance; they do not replace it. Keep app-facing operations typed and deterministic authority local. Codex runs server-side, uses the supplied named credential only, remains gated on compatibility, and cannot replace Gemini/Groq/offline paths with unverified success. An isolated experimental app-server adapter is acceptable to inspect installed capabilities; production support must not be implied.

Keep IntegratedAIState opaque in native persistence until the owning feature decodes it; preserve bytes during unrelated household/home/place/plan edits. Resetting/selecting an example explicitly starts fresh state even when its household ID matches the currently selected example. Failed writes must not publish the reset. Opaque data may contain protected accepted wording and must never be printed in engineering diagnostics.
