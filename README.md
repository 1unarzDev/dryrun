# Dry Run

Dry Run is an iOS app for families to rehearse the first minutes and the next 72 hours of a disaster in their own
household. The rehearsals show how one failure causes others, let the family compare preparations, and leave them
with a plan they can open offline.

> **Current workflow: Mac implementation and continuous iPhone verification.**
> The plugged-in iPhone 16 Pro is the primary native acceptance device. Current work,
> verification dimensions and outstanding gates are tracked in the [integration ledger](docs/integration/ledger.md)
> and [continuation note](docs/integration/continuation.md). Historical verification remains historical evidence.
> App-AI responses, captures and logs are restricted to dedicated output reviewers.

Current corrective work implements six distinct portable hazard mechanics, grounded Gemini task generation, automatic resource research, and retiring practice checks. Read the [six-scenario coverage](docs/ai/six-scenario-coverage.md), [current evaluation](docs/ai/evaluation-report.md), and [exact Mac/iPhone handoff](docs/ai/mac-corrective-handoff.md). Native integration/device checks and independent content review remain required; this is not a completed native release.

The complete supplied specification is [DryRun_AI_Implementation_Reference.md](DryRun_AI_Implementation_Reference.md); the requested `.txt` file is absent. `scripts/verify-ai-portable.sh` runs offline checks. The [private gateway](services/ai-orchestrator/README.md) has separate synthetic live evaluations; provider secrets stay server-side.

## What runs today

| Component | How to run | Status |
|---|---|---|
| `packages/DryRunCore`: models, simulation, ranking, routing, plan builder (Foundation-only) | Native `swift test` through the protected capture wrapper | Current evidence in integration ledger |
| `packages/DryRunVault`: encrypted vault, public pack cache | `scripts/swift.sh packages/DryRunVault test` | Tested (Linux uses swift-crypto; Keychain/file protection need a device) |
| `services/public-api`: Hono public-data Worker | `cd services/public-api && pnpm install && pnpm test` · local: `pnpm dev` | Tested locally, not deployed |
| `apps/ios`: SwiftUI app | `cd apps/ios && xcodegen && open DryRun.xcodeproj` · `scripts/mac/verify.sh` | Current native build/UI/device checks pending |

### Requirements
- Core/vault: Docker (the `swift:6.2` image) **or** Swift 6 / Xcode 26 on macOS.
- iOS app: macOS with Xcode 26 (iOS 18 deployment target) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  RoomPlan scanning needs a LiDAR iPhone; everything else works without LiDAR.
- Backend: Node 22+ and pnpm. No API keys are needed: the app runs fully on bundled data.

## Core journey

Prepare → add family/contact information → optionally establish home and meeting places → rehearse a short
scenario → resolve one practical preparation → share/print the live plan. No scan, account, address, or medical
equipment is needed for the family emergency card. Example homes remain explicitly fictional.

The three destinations are **Prepare, Rehearse, Plan**; settings/language are in the toolbar. All six hazards remain,
with shared deterministic fire/flood/tornado spatial states. Live Apple maps/search/directions are online planning
aids. Contacts, saved places, retained plans and home geometry remain local/offline.

See [DEMO_SCRIPT](docs/DEMO_SCRIPT.md) for the current fictional journey and
[REVISION_EVIDENCE](docs/REVISION_EVIDENCE.md) for implementation/verification limits. This native SwiftUI app cannot
run in Expo Go; use Xcode and `scripts/mac/device.sh` for iPhone installation.

## Fictional data only
Every household, home, and phone number (555-01xx) in `fixtures/` and `content/` is fictional.

## On a Mac
Start with the [current source map](docs/integration/source-map.md) and integration ledger. Use native Mac builds
through `scripts/review/firewall.py capture -- <command>`; only designated reviewers inspect captured logs and
release diagnostics. Regenerate the project with XcodeGen before building. Reserve the connected phone before
launching, resetting, testing or capturing. Legacy Mac scripts remain available, but their raw screenshots,
accessibility exports, logs and PDFs require reviewer handling. A simulator or portable pass does not establish
physical-device verification. Safety text/translations remain unreviewed drafts.

## Docs
`docs/FRONTEND_HANDOFF.md` · `docs/MACOS_VERIFICATION.md` · `docs/DEVICE_CHECKLIST.md` · `docs/ARCHITECTURE.md` · `docs/DECISIONS.md` · `docs/VERIFICATION.md` · `docs/SAFETY_AND_CONTENT.md` ·
`docs/AI_ASSISTANCE.md` · `docs/STUDENT_IMPLEMENTATION.md` · `docs/REVIEW.md` · `docs/BACKLOG.md` · `docs/CONTRACTS.md`
· lane reports and adversarial reviews in `docs/lanes/`.


Current synthetic live results and failures: [live corrective audit](docs/ai/live-corrective-audit.md). Authorized-key availability and official zero-spend options: [Gemini free limits](docs/ai/gemini-free-limits.md). The latest complete Gemini attempt passed2/6 bounded executable continuation checks (with known wording defects); the latest Groq completion attempt finished0/6 because of quota/circuit blocking, while all six deterministic hazard rows and24 branch replays pass. Native integration/device and independent human checks remain open.
