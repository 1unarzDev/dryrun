# Dry Run

Dry Run is an iOS app for families to rehearse the first minutes and the next 72 hours of a disaster in their own
household. The rehearsals show how one failure causes others, let the family compare preparations, and leave them
with a plan they can open offline.

> **October 17 revision: Implementation prepared; native build and device test pending.**
> Portable core/vault/backend verification is recorded in [VERIFICATION](docs/VERIFICATION.md).
> Earlier native results predate this revision. Continue native testing with
> [CLAUDE_NATIVE_HANDOFF](docs/CLAUDE_NATIVE_HANDOFF.md). Safety text/translations remain unreviewed drafts.

## What runs today

| Component | How to run | Status |
|---|---|---|
| `packages/DryRunCore`: models, simulation, ranking, routing, plan builder (Foundation-only) | `scripts/swift.sh packages/DryRunCore test` (Swift 6.2 in Docker) or `swift test` on macOS | Tested |
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
See `docs/MACOS_VERIFICATION.md`. `scripts/mac/verify.sh` produces one bundle to send back. For UI work, see
`docs/FRONTEND_HANDOFF.md`, `scripts/mac/screens.sh`, and `scripts/mac/device.sh`. From Linux, an external Mac can
be driven with `scripts/remote-mac.sh`.

## Docs
`docs/FRONTEND_HANDOFF.md` · `docs/MACOS_VERIFICATION.md` · `docs/DEVICE_CHECKLIST.md` · `docs/ARCHITECTURE.md` · `docs/DECISIONS.md` · `docs/VERIFICATION.md` · `docs/SAFETY_AND_CONTENT.md` ·
`docs/AI_ASSISTANCE.md` · `docs/STUDENT_IMPLEMENTATION.md` · `docs/REVIEW.md` · `docs/BACKLOG.md` · `docs/CONTRACTS.md`
· lane reports and adversarial reviews in `docs/lanes/`.
